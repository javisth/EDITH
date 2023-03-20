//
//  ContentView.swift
//  EDITH
//
//  Created by Javisth Chabria on 18/03/23.
//



import SwiftUI
import ARKit
import SceneKit
import CoreML
import Vision
import Speech

struct ARViewContainer: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.scene = SCNScene()

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config, options: [])

        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true
        arView.showsStatistics = true

        // Add a tap gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        arView.addGestureRecognizer(tapGestureRecognizer)

        // Add the gesture recognizers
        arView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap)))
        arView.addGestureRecognizer(context.coordinator.createLongPressGestureRecognizer())

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    class Coordinator: NSObject, ARSCNViewDelegate {
        // Add these properties at the top of your Coordinator class
        private let audioEngine = AVAudioEngine()
        private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
        private let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        func createSubtitleTextNode(with text: String) -> SCNNode {

            let textGeometry = SCNText(string: text, extrusionDepth: 0.01)
            textGeometry.font = UIFont.systemFont(ofSize: 1.0)
            textGeometry.flatness = 0.1
            textGeometry.firstMaterial?.diffuse.contents = UIColor.white

            let textNode = SCNNode(geometry: textGeometry)

            let (minBound, maxBound) = textNode.boundingBox
            textNode.pivot = SCNMatrix4MakeTranslation(0.5 * (maxBound.x - minBound.x), 0.5 * (minBound.y - maxBound.y), 0)
            textNode.scale = SCNVector3(0.5, 0.5, 0.5) // Increase the scale to make the text bigger

            return textNode
        }


        func startSpeechRecognition(in arView: ARSCNView) {
            let recognitionRequest = SFSpeechAudioBufferRecognitionRequest() // Create a new request object

            let inputNode = audioEngine.inputNode

            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()

            do {
                try audioEngine.start()
            } catch {
                print("Audio engine failed to start: \(error.localizedDescription)")
                return
            }
            
            speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        let spokenText = result.bestTranscription.formattedString
                        
                        // Remove the old subtitle node
                        arView.scene.rootNode.enumerateChildNodes { (node, _) in
                            if node.name == "subtitle" {
                                node.removeFromParentNode()
                            }
                        }
                        
                        // Add the new subtitle node
                        let subtitleNode = self.createSubtitleTextNode(with: spokenText)
                        subtitleNode.position = SCNVector3(0, -3, -5)
                        subtitleNode.name = "subtitle"
                        arView.pointOfView?.addChildNode(subtitleNode)
                        
                        /*
                        
                        //let currentPosition = arView.pointOfView!.position
                        let currentPosition = SCNVector3(0, -0.2, -1) // Set the position relative to the camera node
                        guard let cameraNode = arView.pointOfView else { return }
                        
                        // Create the text node
                        let textNode = self.createSubtitleTextNode(with: spokenText)
                        textNode.position = currentPosition
                        
                        // Add the textNode as a child of the cameraNode
                        cameraNode.addChildNode(textNode)
                        self.addCustomNode(at: currentPosition, with: spokenText, to: arView.scene)
                         */
                        self.audioEngine.stop()
                        recognitionRequest.endAudio()
                        inputNode.removeTap(onBus: 0)
                    }
                } else if let error = error {
                    if error.localizedDescription == "No speech detected" {
                        print("No speech detected. Please try again.")
                    } else {
                        print("Error during speech recognition: \(error.localizedDescription)")
                    }
                }
            }
        }
        


        var arViewContainer: ARViewContainer

        init(_ arViewContainer: ARViewContainer) {
            self.arViewContainer = arViewContainer
        }

        @objc func handleTap(sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARSCNView else { return }
            let touchLocation = sender.location(in: arView)

            let raycastQuery = arView.raycastQuery(from: touchLocation, allowing: .estimatedPlane, alignment: .any)

            if let raycastResult = arView.session.raycast(raycastQuery!).first {
                let position = SCNVector3Make(raycastResult.worldTransform.columns.3.x, raycastResult.worldTransform.columns.3.y, raycastResult.worldTransform.columns.3.z)

                performFaceDetection(at: touchLocation, in: arView) { faceDetected in
                    if faceDetected {
                        DispatchQueue.main.async {
                            self.addCustomNode(at: position, with: "Face detected!", to: arView.scene)
                        }
                    } else {
                        self.performObjectRecognition(at: touchLocation, in: arView) { objectName in
                            DispatchQueue.main.async {
                                let labelText = "\(objectName)"
                                self.addCustomNode(at: position, with: labelText, to: arView.scene)
                            }
                        }
                    }
                }
            }
        }

        func createLongPressGestureRecognizer() -> UILongPressGestureRecognizer {
            let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            longPressRecognizer.minimumPressDuration = 1
            return longPressRecognizer
        }

        @objc func handleLongPress(sender: UILongPressGestureRecognizer) {
            guard let arView = sender.view as? ARSCNView else { return }

            if sender.state == .began {
                startSpeechRecognition(in: arView)
            }
        }
        
        /*
        func createCustomNode(withText text: String) -> SCNNode {
            let node = SCNNode()
            let textGeometry = SCNText(string: text, extrusionDepth: 1)
            textGeometry.font = UIFont.systemFont(ofSize: 1)
            textGeometry.flatness = 0.1
            let textNode = SCNNode(geometry: textGeometry)
            textNode.scale = SCNVector3(0.01, 0.01, 0.01)
            
            let (min, max) = textGeometry.boundingBox
            let width = CGFloat(max.x - min.x)
            let plane = SCNPlane(width: width * 0.013, height: 0.05)
            plane.cornerRadius = 0.01
            let planeNode = SCNNode(geometry: plane)
            planeNode.position = SCNVector3(CGFloat(min.x) * 0.013, 0, 0)

            node.addChildNode(planeNode)
            node.addChildNode(textNode)
            
            return node
        }
        */
        func createCustomNode(withText text: String) -> SCNNode {
            let textGeometry = SCNText(string: text, extrusionDepth: 0.5)
            textGeometry.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            textGeometry.flatness = 0.01

            let textMaterial = SCNMaterial()
            textMaterial.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.8)
            textMaterial.specular.contents = UIColor.white
            textMaterial.shininess = 0.8
            textGeometry.materials = [textMaterial]

            let textNode = SCNNode(geometry: textGeometry)
            textNode.scale = SCNVector3(0.01, 0.01, 0.01)

            let (min, max) = textGeometry.boundingBox
            let textWidth = CGFloat(max.x - min.x)
            let textHeight = CGFloat(max.y - min.y)

            let plane = SCNPlane(width: textWidth * 0.01, height: textHeight * 0.01)
            plane.cornerRadius = 0.005
            let planeMaterial = SCNMaterial()
            planeMaterial.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.3)
            planeMaterial.specular.contents = UIColor.white
            planeMaterial.shininess = 0.5
            plane.materials = [planeMaterial]

            let planeNode = SCNNode(geometry: plane)
            planeNode.opacity = 0.5
            planeNode.position = SCNVector3(textWidth * 0.005, -textHeight * 0.005, -0.01)

            let parentNode = SCNNode()
            parentNode.addChildNode(textNode)
            parentNode.addChildNode(planeNode)
            

            return parentNode
        }
         
        


        func addCustomNode(at position: SCNVector3, with text: String, to scene: SCNScene) {
            let customNode = createCustomNode(withText: text)
            customNode.position = position
            scene.rootNode.addChildNode(customNode)
            //addRotationAnimation(to: customNode)
        }
/*
        func addRotationAnimation(to node: SCNNode) {
            let rotation = CABasicAnimation(keyPath: "rotation")
            rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, CGFloat.pi * 2))
            rotation.duration = 10
            rotation.repeatCount = .greatestFiniteMagnitude
            node.addAnimation(rotation, forKey: "rotation")
        }
*/
        // Remaining code
        func performObjectRecognition(at point: CGPoint, in arView: ARSCNView, completion: @escaping (String) -> Void) {
            guard let pixelBuffer = arView.session.currentFrame?.capturedImage else { return }
            
            do {
                let modelConfiguration = MLModelConfiguration()
                let model = try VNCoreMLModel(for: MobileNetV2(configuration: modelConfiguration).model)
                let request = VNCoreMLRequest(model: model) { request, error in
                    guard let results = request.results as? [VNClassificationObservation], let topResult = results.first else {
                        completion("Unknown")
                        return
                    }
                    
                    completion(topResult.identifier)
                }
                
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                try handler.perform([request])
            } catch {
                print("Error creating the VNCoreMLModel: \(error.localizedDescription)")
            }
        }

        func performFaceDetection(at point: CGPoint, in arView: ARSCNView, completion: @escaping (Bool) -> Void) {
            guard let pixelBuffer = arView.session.currentFrame?.capturedImage else { return }
            
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard let results = request.results as? [VNFaceObservation] else {
                    completion(false)
                    return
                }
                
                let faceDetected = results.contains { observation in
                    let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
                    let viewSize = arView.bounds.size
                    
                    let rectWidth = observation.boundingBox.width * imageSize.width
                    let rectHeight = observation.boundingBox.height * imageSize.height
                    
                    let rectX = observation.boundingBox.origin.x * imageSize.width
                    let rectY = (1 - observation.boundingBox.origin.y) * imageSize.height - rectHeight
                    
                    let viewRect = CGRect(x: rectX * viewSize.width / imageSize.width,
                                          y: rectY * viewSize.height / imageSize.height,
                                          width: rectWidth * viewSize.width / imageSize.width,
                                          height: rectHeight * viewSize.height / imageSize.height)
                    
                    return viewRect.contains(point)
                }
                
                completion(faceDetected)
            }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            try? handler.perform([request])
        }
        
        
    }
}

struct ContentView: View {
    @State private var labelText = "Hello, AR!"

    var body: some View {
        ARViewContainer(text: $labelText)
    }
}
        

           

