//
//  distributionOBJController.swift
//  distributionOBJ
//
//  Created by 徳田泰地 on 2024/06/18.
//

import UIKit
import Vision
import RealityKit
import ARKit

class distributionOBJController: UIViewController, ARSessionDelegate {
    
    private var arView:ARView!
    lazy var request:VNRequest = {
        var handPoseRequest = VNDetectHumanHandPoseRequest(completionHandler: handDetectionCompletionHandler)
        handPoseRequest.maximumHandCount = 1
        return handPoseRequest
    }()
    var viewWidth:Int = 0
    var viewHeight:Int = 0
    var box:ModelEntity!
    var brocks:[ModelEntity?] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARView(frame: view.bounds)
        arView.session.delegate = self
        view.addSubview(arView)
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
//        config.frameSemantics = [.personSegmentation]
        //framesemanticsにはA12Bionic以上が必要だが、8+はA11Bionicであるため対応していない
        config.planeDetection = [.horizontal]
        arView.session.run(config, options: [])
        viewWidth = Int(arView.bounds.width)
        viewHeight = Int(arView.bounds.height)
        setupObject()
    }
    
    
    private func setupObject(){
        let anchor = AnchorEntity(plane: .horizontal)
        
        let plane = ModelEntity(mesh: .generatePlane(width: 2, depth: 2), materials: [OcclusionMaterial()])
        anchor.addChild(plane)
        plane.generateCollisionShapes(recursive: false)
        plane.physicsBody = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .static)
        
//        box = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .white, isMetallic: true)])
//        box.generateCollisionShapes(recursive: false)
//        box.physicsBody = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .dynamic)
//        box.position = [0,0.025,0]
//        anchor.addChild(box)
//        arView.scene.addAnchor(anchor)
        brocks.append(makeBrock(arView: arView, anchor: anchor))
    }
    
    var recentIndexFingerPoint:CGPoint = .zero
    var recentThumbFingerPoint:CGPoint = .zero
    
    func handDetectionCompletionHandler(request: VNRequest?, error: Error?) { // インタラクション部分
        guard let observation = request?.results?.first as? VNHumanHandPoseObservation else { return }
        guard let indexFingerTip = try? observation.recognizedPoints(.all)[.indexTip],
              indexFingerTip.confidence > 0.3 else {return}
        guard let thumbFingerTip = try? observation.recognizedPoints(.all)[.thumbTip],
              thumbFingerTip.confidence > 0.3 else {return}
        let normalizedIndexPoint = VNImagePointForNormalizedPoint(CGPoint(x: indexFingerTip.location.y, y: indexFingerTip.location.x), viewWidth,  viewHeight)
        let normalizedThumbPoint = VNImagePointForNormalizedPoint(CGPoint(x: thumbFingerTip.location.y, y: thumbFingerTip.location.x), viewWidth,  viewHeight)
        // 人差し指と親指の座標と重なっているオブジェクトを抽出し、それらが同じオブジェクトであるなら該当オブジェクトを代入
        if let entity = arView.entity(at: normalizedIndexPoint) as? ModelEntity,   // 人差し指
            let entity2 = arView.entity(at: normalizedThumbPoint) as? ModelEntity, //　親指
            entity == brocks[0] && entity2 == brocks[0] {
            HandtrackingHandler(entity: entity)
        }
        // 指の位置を更新
        recentIndexFingerPoint = normalizedIndexPoint
        recentThumbFingerPoint = normalizedThumbPoint
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let handler = VNImageRequestHandler(cvPixelBuffer:pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([(self?.request)!])
                
            } catch let error {
                print(error)
            }
        }
    }
}

// オブジェクトに触れた後のハンドラー
func HandtrackingHandler (entity: ModelEntity) {
    entity.addForce([0,40,0], relativeTo: nil)
}

// オブジェクト情報の設定
func makeBrock (arView:ARView, anchor:AnchorEntity) -> ModelEntity?{
    var brock:ModelEntity!
    // オブジェクトの形（メッシュ）と見た目（マテリアル）
    brock = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .white, isMetallic: true)])
    // オブジェクトの衝突を検出する
    brock.generateCollisionShapes(recursive: false)
    // オブジェクトに物理演算を適用？
    brock.physicsBody = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .dynamic)
    // 座標を設定
    brock.position = [0,0.025,0]
    // オブジェクトをアンカーと接続
    anchor.addChild(brock)
    // アンカーをARViewツリーと接続
    arView.scene.addAnchor(anchor)
    return brock
}
