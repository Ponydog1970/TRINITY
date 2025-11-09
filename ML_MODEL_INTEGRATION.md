# ML Model Integration Guide - TRINITY Vision Aid

## Overview

This guide explains how to integrate real Core ML models into TRINITY for production use. Currently, the perception agent uses placeholder implementations. This guide will walk you through integrating YOLOv8, MobileNetV3, and custom models.

---

## Prerequisites

### Required Tools

1. **Xcode 15.0+** with Core ML Tools
2. **Python 3.8+** for model conversion
3. **coremltools** Python package

```bash
pip install coremltools torch torchvision ultralytics
```

---

## Model Integration Steps

### 1. Object Detection - YOLOv8

YOLOv8 is recommended for real-time object detection on iPhone.

#### Step 1.1: Download Pre-trained Model

```bash
# Install ultralytics
pip install ultralytics

# Download YOLOv8 nano model (optimized for mobile)
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"
```

#### Step 1.2: Convert to Core ML

Create `convert_yolo.py`:

```python
from ultralytics import YOLO
import coremltools as ct

# Load YOLOv8 model
model = YOLO('yolov8n.pt')

# Export to Core ML
model.export(
    format='coreml',
    imgsz=640,  # Input size
    nms=True,   # Include NMS
    half=True   # Use FP16 for smaller size
)

print("✅ YOLOv8 converted to Core ML: yolov8n.mlpackage")
```

Run conversion:
```bash
python convert_yolo.py
```

#### Step 1.3: Add to Xcode Project

1. Drag `yolov8n.mlpackage` into Xcode project
2. Target Membership: TRINITY
3. Xcode will auto-generate Swift interface

#### Step 1.4: Update PerceptionAgent

```swift
// PerceptionAgent.swift

import Vision
import CoreML

class PerceptionAgent: BaseAgent<PerceptionInput, PerceptionOutput> {
    private let visionModel: VNCoreMLModel?

    init(embeddingGenerator: EmbeddingGenerator) throws {
        // Load YOLOv8 model
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use Neural Engine + GPU

        let model = try yolov8n(configuration: config).model
        self.visionModel = try VNCoreMLModel(for: model)

        super.init(name: "PerceptionAgent")
    }

    private func processVisionFrame(_ imageData: Data) async throws -> [DetectedObject] {
        guard let visionModel = visionModel else {
            throw PerceptionError.modelNotLoaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Create Vision request
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Convert to DetectedObject
                let objects = results.compactMap { observation -> DetectedObject? in
                    guard let label = observation.labels.first?.identifier,
                          observation.confidence > 0.5 else {
                        return nil
                    }

                    let bbox = observation.boundingBox
                    return DetectedObject(
                        id: UUID(),
                        label: label,
                        confidence: observation.confidence,
                        boundingBox: BoundingBox(
                            x: Float(bbox.midX),
                            y: Float(bbox.midY),
                            z: 0,
                            width: Float(bbox.width),
                            height: Float(bbox.height),
                            depth: 0
                        ),
                        spatialData: nil
                    )
                }

                continuation.resume(returning: objects)
            }

            // Process image
            guard let cgImage = createCGImage(from: imageData) else {
                continuation.resume(returning: [])
                return
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

---

### 2. Image Feature Extraction - MobileNetV3

For embedding generation, use MobileNetV3 or Vision Framework's feature print.

#### Step 2.1: Option A - Use Built-in Vision Framework (Recommended)

```swift
// EmbeddingGenerator.swift

func generateEmbedding(from image: Data) async throws -> [Float] {
    guard let cgImage = createCGImage(from: image) else {
        throw EmbeddingError.invalidImage
    }

    return try await withCheckedThrowingContinuation { continuation in
        let request = VNGenerateImageFeaturePrintRequest { request, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }

            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                continuation.resume(throwing: EmbeddingError.noFeatures)
                return
            }

            // Vision's feature print is already 512d
            let embedding = self.convertFeaturePrint(observation)
            continuation.resume(returning: embedding)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
```

#### Step 2.2: Option B - Custom MobileNetV3

```python
# convert_mobilenet.py

import torch
import torchvision
import coremltools as ct

# Load pretrained MobileNetV3
model = torchvision.models.mobilenet_v3_small(pretrained=True)
model.eval()

# Trace model
example_input = torch.rand(1, 3, 224, 224)
traced_model = torch.jit.trace(model, example_input)

# Convert to Core ML
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.ImageType(name="image", shape=(1, 3, 224, 224))],
    compute_units=ct.ComputeUnit.ALL
)

# Save
mlmodel.save("MobileNetV3Small.mlpackage")
print("✅ MobileNetV3 converted")
```

---

### 3. Text Embeddings - Sentence Transformers

For semantic text embeddings, convert a sentence transformer model.

#### Step 3.1: Export from HuggingFace

```python
# convert_text_encoder.py

from transformers import AutoTokenizer, AutoModel
import torch
import coremltools as ct

# Load model
model_name = "sentence-transformers/all-MiniLM-L6-v2"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModel.from_pretrained(model_name)

# Create traced model
class SentenceEncoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        outputs = self.model(input_ids, attention_mask)
        # Mean pooling
        embeddings = outputs[0].mean(dim=1)
        return embeddings

encoder = SentenceEncoder(model)
encoder.eval()

# Trace
example_input = {
    'input_ids': torch.randint(0, 1000, (1, 128)),
    'attention_mask': torch.ones(1, 128)
}

traced = torch.jit.trace(encoder, (example_input['input_ids'], example_input['attention_mask']))

# Convert
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, 128)),
        ct.TensorType(name="attention_mask", shape=(1, 128))
    ]
)

mlmodel.save("SentenceEncoder.mlpackage")
```

---

## Performance Optimization

### 1. Model Quantization

Reduce model size with FP16 or INT8 quantization:

```python
import coremltools as ct

# Load model
model = ct.models.MLModel("yolov8n.mlpackage")

# Quantize to FP16
model_fp16 = ct.models.neural_network.quantization_utils.quantize_weights(
    model, nbits=16
)

model_fp16.save("yolov8n_fp16.mlpackage")
```

### 2. Compute Units Configuration

```swift
let config = MLModelConfiguration()

// Option 1: All (Neural Engine + GPU + CPU)
config.computeUnits = .all  // Best for most models

// Option 2: CPU and Neural Engine only
config.computeUnits = .cpuAndNeuralEngine

// Option 3: CPU only
config.computeUnits = .cpuOnly
```

### 3. Batch Processing

Process multiple frames in batch for better throughput:

```swift
// EmbeddingGenerator.swift

func generateEmbeddings(from observations: [Observation]) async throws -> [[Float]] {
    return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
        for (index, observation) in observations.enumerated() {
            group.addTask {
                let embedding = try await self.generateEmbedding(from: observation)
                return (index, embedding)
            }
        }

        var results: [(Int, [Float])] = []
        for try await result in group {
            results.append(result)
        }

        return results
            .sorted { $0.0 < $1.0 }
            .map { $1 }
    }
}
```

---

## Testing Your Integration

### Unit Test for Model Loading

```swift
// ModelTests.swift

import XCTest
@testable import TRINITY

class ModelIntegrationTests: XCTestCase {
    func testYOLOv8Loading() throws {
        let config = MLModelConfiguration()
        let model = try yolov8n(configuration: config)
        XCTAssertNotNil(model)
    }

    func testObjectDetection() async throws {
        let agent = try PerceptionAgent(embeddingGenerator: EmbeddingGenerator())

        // Load test image
        let testImage = loadTestImage(named: "test_scene.jpg")

        let input = PerceptionInput(
            cameraFrame: testImage,
            depthData: nil,
            arFrame: nil,
            timestamp: Date()
        )

        let output = try await agent.process(input)

        XCTAssertGreaterThan(output.detectedObjects.count, 0)
    }
}
```

---

## Model Performance Benchmarks

Target performance on iPhone 15 Pro:

| Model | Size | Inference Time | Accuracy |
|-------|------|----------------|----------|
| YOLOv8n | 6.2 MB | ~15ms | mAP 37.3 |
| YOLOv8s | 22 MB | ~25ms | mAP 44.9 |
| MobileNetV3 | 5.4 MB | ~8ms | Top-1 67.4% |
| Vision FeaturePrint | Built-in | ~12ms | N/A |

---

## Troubleshooting

### Issue: Model Not Found

```swift
// Check if model exists
guard let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") else {
    fatalError("Model not found in bundle")
}
```

### Issue: Out of Memory

- Use FP16 quantization
- Reduce input size
- Process frames less frequently

### Issue: Slow Inference

- Check `computeUnits` is set to `.all`
- Reduce model complexity (use nano/small variants)
- Enable GPU acceleration in Xcode settings

---

## Next Steps

1. ✅ Integrate YOLOv8 for object detection
2. ✅ Test with real device (not simulator)
3. ✅ Profile with Instruments
4. ✅ Optimize for battery life
5. ✅ Fine-tune for specific use cases

---

## Resources

- [Apple Core ML Documentation](https://developer.apple.com/documentation/coreml)
- [YOLOv8 Documentation](https://docs.ultralytics.com)
- [Core ML Tools](https://coremltools.readme.io)
- [Apple Machine Learning](https://developer.apple.com/machine-learning)

---

**Integration Status**: 📋 Ready for implementation
**Last Updated**: 2025-01-09
