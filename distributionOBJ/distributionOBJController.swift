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
import SceneKit
import Combine
import AVFoundation

class distributionOBJController: UIViewController, ARSessionDelegate {
    
    private var arView:ARView!
    var audioPlayer:AVAudioPlayer?
    lazy var request:VNRequest = {
        var handPoseRequest = VNDetectHumanHandPoseRequest(completionHandler: handDetectionCompletionHandler)
        handPoseRequest.maximumHandCount = 1
        return handPoseRequest
    }()
    var viewWidth:Int = 0
    var viewHeight:Int = 0
    var blocklist:[ModelEntity?] = []
    let colorlist = [1,2,3,4,5,6,7,8,9,10,11,4,6,5,9,2,11,1,3,7,10,8]
    let colorlisttest = [0,1]
    var catchablelist = [0,0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0,0,0,0,1,1]
    var blocklocation:[SIMD3<Float>] = []

    
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
        // ブロック情報の作成
//        blocklist = makeBlockListTest(anchor: anchor) // テスト
        blocklist = makeBlockList(anchor: anchor)
        print("blocklist is \(blocklist.count)")
    }
    
    var recentIndexFingerPoint:CGPoint = .zero
    var recentThumbFingerPoint:CGPoint = .zero
    var catchflag = 0
    var preCatchblock:ModelEntity? = nil
    var preCatchblockNum = -1
    var collisionSubscriber:Cancellable?
    
    // インタラクション部分
    func handDetectionCompletionHandler(request: VNRequest?, error: Error?) {
            
        guard let observation = request?.results?.first as? VNHumanHandPoseObservation else { return }
        // 人差し指と親指の設定
        guard let indexFingerTip = try? observation.recognizedPoints(.all)[.indexTip],
              indexFingerTip.confidence > 0.3 else {return}
        guard let thumbFingerTip = try? observation.recognizedPoints(.all)[.thumbTip],
              thumbFingerTip.confidence > 0.3 else {return}
        let normalizedIndexPoint = VNImagePointForNormalizedPoint(CGPoint(x: indexFingerTip.location.y, y: indexFingerTip.location.x), viewWidth,  viewHeight)
        let normalizedThumbPoint = VNImagePointForNormalizedPoint(CGPoint(x: thumbFingerTip.location.y, y: thumbFingerTip.location.x), viewWidth,  viewHeight)
        // 掴んでいるオブジェクトを取得
        let index_entity = arView.entity(at: normalizedIndexPoint) as? ModelEntity // 人差し指
        let thumb_entity = arView.entity(at: normalizedThumbPoint) as? ModelEntity //　親指
        // index_entityがどのブロックかを判定　（−1ならblocklist外のオブジェクト）
        var catchblocknum = identifyNumberinblocklist(Block: index_entity)
        // 人差し指と親指が参照しているブロックが同じなら、そのブロックを取得する
        let catchblock:ModelEntity?
        if catchblocknum != -1 {
            if catchablelist[catchblocknum] == 1 {
                    catchblock = (thumb_entity == index_entity) ? blocklist[catchblocknum] : nil
            } else {
                catchblock = nil
                catchblocknum = -1
            }
        } else {
            catchblock = nil
        }

        
        // 掴んだブロックを記憶しておく
        preCatchblock = (catchblock != nil) ? catchblock : preCatchblock
        preCatchblockNum = (catchblocknum != -1) ? catchblocknum : preCatchblockNum
        
        collisionSubscriber = arView.scene.subscribe(
            to: CollisionEvents.Began.self,
            on: preCatchblock
        ) {event in
            print("collision!!")
            let blockA = event.entityA as? ModelEntity
            let blockAnum = self.identifyNumberinblocklist(Block: blockA)
            let blockB = event.entityB as? ModelEntity
            let blockBnum = self.identifyNumberinblocklist(Block: blockB)
            let collisionblock:ModelEntity?
            if blockAnum != -1 && self.preCatchblockNum != blockAnum {
                collisionblock = blockA
            } else if blockBnum != -1 && self.preCatchblockNum != blockBnum {
                collisionblock = blockB
            } else {
                collisionblock = nil
            }
            
            let collisionblocknum:Int
            if blockAnum != -1 && self.preCatchblockNum != blockAnum {
                collisionblocknum = blockAnum
            } else if blockBnum != -1 && self.preCatchblockNum != blockBnum {
                collisionblocknum = blockBnum
            } else {
                collisionblocknum = -1
            }
            
            // ブロックの消去判定
            print("collisionblock[\(collisionblocknum)] preCatchblock[\(self.preCatchblockNum)]")
            //            self.preCatchblock?.physicsBody?.mode = .static
            // 接触しているブロックがある
            if collisionblocknum != -1 && self.preCatchblockNum != -1 && self.catchflag == 1 {
                if self.catchablelist[collisionblocknum] == 1 {
                    // 色が同じ
                    if self.colorlist[self.preCatchblockNum] == self.colorlist[collisionblocknum] {
                        self.preCatchblock!.removeFromParent()
                        collisionblock!.removeFromParent()
                        self.playSound(filename: "vanishment", filetype: "mp3")
                        self.catchablelist[self.preCatchblockNum] = -1
                        self.catchablelist[collisionblocknum] = -1
                    }
                }
            }
        }
        
        // 掴み処理開始
        if catchblock != nil {  // ブロックを掴んでいる
            print("Through flag=\(catchflag)")
            if catchflag == 0 {
                print("blockposition\(String(describing: blocklocation[catchblocknum]))")
                // 音を鳴らす
                playSound(filename: "catching", filetype: "mp3")
            }
            catchflag = 1
            //  キャッチ時ハンドラーを使用
            catchObjectHandlerTest(block: catchblock)  // テスト
//            catchBlockHandler(catchblock: catchblock, num: catchblocknum, point: normalizedIndexPoint) //　本番
        } else {                // ブロックを掴んでいない
            print("Through2 flag=\(catchflag)")
            if catchflag == 1 {     // 前にブロックを掴んでいた（ブロックを離した）
                print("release!!")
                catchflag = 0   // フラグをリセット
                // オブジェクトを離した時ハンドラー
                releaseObjectHandler()
            }
            //　元の位置に戻す
            for (num, block) in blocklist.enumerated() {
                block?.position = blocklocation[num]
            }
        }
        // 指の位置を更新
        recentIndexFingerPoint = normalizedIndexPoint
        recentThumbFingerPoint = normalizedThumbPoint
        // ブロックの掴み可能リストを更新
        catchablelistChacker(Catchablelist: catchablelist)
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
    // ブロックリスト内のどのブロックなのかを判定する
    func identifyNumberinblocklist (Block:ModelEntity?) -> Int {
        var blocknum = 0
        for oneblock in blocklist {
            if Block == oneblock {
                return blocknum // 同じブロックならその番号を返す
            } else {
                blocknum += 1
            }
        }
        return -1  // ブロックリスト外のオブジェクトなら-1を返す
    }
    // オブジェクト情報の設定（テスト）
    func makeBlockListTest (anchor:AnchorEntity) -> [ModelEntity?] {
        var blocklist:[ModelEntity?] = []
        var block:ModelEntity!
        // オブジェクトの形（メッシュ）と見た目（マテリアル）
        block = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .white, isMetallic: true)])
        // オブジェクトの衝突を検出するための当たり判定を作る
        block.generateCollisionShapes(recursive: false)
        // オブジェクトに物理演算を適用？
//        block.physicsBody = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .static)
        // 座標を設定　[0,0.025,0]
        block.position = [0,0.025,0]
        // オブジェクトをアンカーと接続
        anchor.addChild(block)
        // アンカーをARViewツリーと接続
        arView.scene.addAnchor(anchor)
        
        blocklist.append(block)
        
        block = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .red, isMetallic: true)])
        // オブジェクトの衝突を検出するための当たり判定を作る
        block.generateCollisionShapes(recursive: false)
        // オブジェクトに物理演算を適用？
//        block.physicsBody = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .static)
        // 座標を設定　[0,0.025,0]
        block.position = [0,0.025,0.1]
        // オブジェクトをアンカーと接続
        anchor.addChild(block)
        
        // アンカーをARViewツリーと接続
        arView.scene.addAnchor(anchor)
        
        blocklist.append(block)
        return blocklist
    }
    // ブロック設定
    func makeBlockList (anchor:AnchorEntity) -> [ModelEntity?] {
        var blocklist:[ModelEntity?] = []
        var box1:ModelEntity!
        var box2:ModelEntity!
        var box3:ModelEntity!
        var box4:ModelEntity!
        var box5:ModelEntity!
        var box6:ModelEntity!
        var box7:ModelEntity!
        var box8:ModelEntity!
        var box9:ModelEntity!
        var box10:ModelEntity!
        var box11:ModelEntity!
        var box12:ModelEntity!
        var box13:ModelEntity!
        var box14:ModelEntity!
        var box15:ModelEntity!
        var box16:ModelEntity!
        var box17:ModelEntity!
        var box18:ModelEntity!
        var box19:ModelEntity!
        var box20:ModelEntity!
        var box21:ModelEntity!
        var box22:ModelEntity!
        
        box1 = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .white, isMetallic: true)])
        box1.generateCollisionShapes(recursive: false)
        box1.position = [0,0.025,0]
        blocklocation.append([0,0.025,0])
        anchor.addChild(box1)
        blocklist.append(box1)
        
        box2 = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .red, isMetallic: true)])
        box2.generateCollisionShapes(recursive: false)
        box2.position = [0.051,0.025,0]
        blocklocation.append([0.051,0.025,0])
        anchor.addChild(box2)
        blocklist.append(box2)
        
        box3 = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .blue, isMetallic: true)])
        box3.generateCollisionShapes(recursive: false)
        box3.position = [0.102,0.025,0]
        blocklocation.append([0.102,0.025,0])
        anchor.addChild(box3)
        blocklist.append(box3)
        
        box4 = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .black, isMetallic: true)])
        box4.generateCollisionShapes(recursive: false)
        box4.position = [-0.051,0.025,0]
        blocklocation.append([-0.051,0.025,0])
        anchor.addChild(box4)
        blocklist.append(box4)
        
        box5 = ModelEntity(mesh: .generateBox(size: 0.05), materials:   [SimpleMaterial(color: .cyan, isMetallic: true)])
        box5.generateCollisionShapes(recursive: false)
        box5.position = [0,0.025,0.051]
        blocklocation.append([0,0.025,0.051])
        anchor.addChild(box5)
        blocklist.append(box5)
        
        box6 = ModelEntity(mesh: .generateBox(size: 0.05), materials:   [SimpleMaterial(color: .magenta, isMetallic: true)])
        box6.generateCollisionShapes(recursive: false)
        box6.position = [0.051,0.025,0.051]
        blocklocation.append([0.051,0.025,0.051])
        anchor.addChild(box6)
        blocklist.append(box6)
        
        box7 = ModelEntity(mesh: .generateBox(size: 0.05), materials:   [SimpleMaterial(color: .green, isMetallic: true)])
        box7.generateCollisionShapes(recursive: false)
        box7.position = [0.102,0.025,0.051]
        blocklocation.append([0.102,0.025,0.051])
        anchor.addChild(box7)
        blocklist.append(box7)
        
        box8 = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .orange, isMetallic: true)])
        box8.generateCollisionShapes(recursive: false)
        box8.position = [-0.051,0.025,0.051]
        blocklocation.append([-0.051,0.025,0.051])
        anchor.addChild(box8)
        blocklist.append(box8)
        
        box9 = ModelEntity(mesh: .generateBox(size: 0.05), materials:   [SimpleMaterial(color: .yellow, isMetallic: true)])
        box9.generateCollisionShapes(recursive: false)
        box9.position = [0,0.025,0.102]
        blocklocation.append([0,0.025,0.102])
        anchor.addChild(box9)
        blocklist.append(box9)
        
        box10 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .purple, isMetallic: true)])
        box10.generateCollisionShapes(recursive: false)
        box10.position = [0.051,0.025,0.102]
        blocklocation.append([0.051,0.025,0.102])
        anchor.addChild(box10)
        blocklist.append(box10)
        
        box11 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .brown, isMetallic: true)])
        box11.generateCollisionShapes(recursive: false)
        box11.position = [0.102,0.025,0.102]
        blocklocation.append([0.102,0.025,0.102])
        anchor.addChild(box11)
        blocklist.append(box11)
        
        box12 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .black, isMetallic: true)])
        box12.generateCollisionShapes(recursive: false)
        box12.position = [-0.051,0.025,0.102]
        blocklocation.append([-0.051,0.025,0.102])
        anchor.addChild(box12)
        blocklist.append(box12)
        
        box13 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .magenta, isMetallic: true)])
        box13.generateCollisionShapes(recursive: false)
        box13.position = [0,0.025,-0.051]
        blocklocation.append([0,0.025,-0.051])
        anchor.addChild(box13)
        blocklist.append(box13)
        
        box14 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .cyan, isMetallic: true)])
        box14.generateCollisionShapes(recursive: false)
        box14.position = [0.051,0.025,-0.051]
        blocklocation.append([0.051,0.025,-0.051])
        anchor.addChild(box14)
        blocklist.append(box14)
        
        box15 = ModelEntity(mesh: .generateBox(size: 0.05), materials: [SimpleMaterial(color: .yellow, isMetallic: true)])
        box15.generateCollisionShapes(recursive: false)
        box15.position = [0.102,0.025,-0.051]
        blocklocation.append([0.102,0.025,-0.051])
        anchor.addChild(box15)
        blocklist.append(box15)
        
        box16 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .red, isMetallic: true)])
        box16.generateCollisionShapes(recursive: false)
        box16.position = [-0.051,0.025,-0.051]
        blocklocation.append([-0.051,0.025,-0.051])
        anchor.addChild(box16)
        blocklist.append(box16)
        
        box17 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .brown, isMetallic: true)])
        box17.generateCollisionShapes(recursive: false)
        box17.position = [0,0.076,0]
        blocklocation.append([0,0.076,0])
        anchor.addChild(box17)
        blocklist.append(box17)
        
        box18 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .white, isMetallic: true)])
        box18.generateCollisionShapes(recursive: false)
        box18.position = [0.051,0.076,0]
        blocklocation.append([0.051,0.076,0])
        anchor.addChild(box18)
        blocklist.append(box18)
        
        box19 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .blue, isMetallic: true)])
        box19.generateCollisionShapes(recursive: false)
        box19.position = [0,0.076,0.051]
        blocklocation.append([0,0.076,0.051])
        anchor.addChild(box19)
        blocklist.append(box19)
        
        box20 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .green, isMetallic: true)])
        box20.generateCollisionShapes(recursive: false)
        box20.position = [0.051,0.076,0.051]
        blocklocation.append([0.051,0.076,0.051])
        anchor.addChild(box20)
        blocklist.append(box20)
        
        box21 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .purple, isMetallic: true)])
        box21.generateCollisionShapes(recursive: false)
        box21.position = [0,0.127,0.025]
        blocklocation.append([0,0.127,0.025])
        anchor.addChild(box21)
        blocklist.append(box21)
        
        box22 = ModelEntity(mesh: .generateBox(size: 0.05), materials:  [SimpleMaterial(color: .orange, isMetallic: true)])
        box22.generateCollisionShapes(recursive: false)
        box22.position = [0.051,0.127,0.025]
        blocklocation.append([0.051,0.127,0.025])
        anchor.addChild(box22)
        blocklist.append(box22)
        
        arView.scene.addAnchor(anchor)
        
        return blocklist
    }
    // オブジェクトを掴んだ時(テスト）
    func catchObjectHandlerTest (block:ModelEntity?) {
        let blockindex = identifyNumberinblocklist(Block: block)
        for (i,iblock) in self.blocklist.enumerated() {
            if i != blockindex {
                if colorlist[i] == colorlist[blockindex] {
                    block?.position = iblock!.position
                }
            }
        }
    }
    
    func catchBlockHandler(catchblock:ModelEntity?, num: Int, point:CGPoint){
        let location = point
        guard let horizontalHit = arView.hitTest(
            location,
            types: .existingPlane
            ).first else {
                return
            }
        let column3: simd_float4 = horizontalHit.worldTransform.columns.3
        let position:SIMD3<Float> = [column3.x, column3.y, column3.z]
        catchblock?.position = position
    }
    // オブジェクトを離したとき
    func releaseObjectHandler () {
//        collisionSubscriber = arView.scene.subscribe(
//            to: CollisionEvents.Began.self,
//            on: preCatchblock
//        ) {event in
//            print("collision!!")
//            let blockA = event.entityA as? ModelEntity
//            let blockAnum = self.identifyNumberinblocklist(Block: blockA)
//            let blockB = event.entityB as? ModelEntity
//            let blockBnum = self.identifyNumberinblocklist(Block: blockB)
//            let collisionblock:ModelEntity?
//            if blockAnum != -1 && self.preCatchblockNum != blockAnum {
//                collisionblock = blockA
//            } else if blockBnum != -1 && self.preCatchblockNum != blockBnum {
//                collisionblock = blockB
//            } else {
//                collisionblock = nil
//            }
//            
//            let collisionblocknum:Int
//            if blockAnum != -1 && self.preCatchblockNum != blockAnum {
//                collisionblocknum = blockAnum
//            } else if blockBnum != -1 && self.preCatchblockNum != blockBnum {
//                collisionblocknum = blockBnum
//            } else {
//                collisionblocknum = -1
//            }
//            
//            // ブロックの消去判定
//            print("collisionblock[\(collisionblocknum)] preCatchblock[\(self.preCatchblockNum)]")
//            //            self.preCatchblock?.physicsBody?.mode = .static
//            // 接触しているブロックがある
//            if collisionblock != nil {
//                if self.catchablelist[collisionblocknum] == 1 {
//                    // 色が同じ
//                    if self.colorlist[self.preCatchblockNum] == self.colorlist[collisionblocknum] {
//                        self.preCatchblock!.removeFromParent()
//                        collisionblock!.removeFromParent()
//                        self.playSound(filename: "vanishment", filetype: "mp3")
//                        self.catchablelist[self.preCatchblockNum] = -1
//                        self.catchablelist[collisionblocknum] = -1
//                    }
//                }
//            }
//        }
        collisionSubscriber
    }
    
    func playSound (filename:String, filetype:String) {
       do {
           audioPlayer = try AVAudioPlayer(data: NSDataAsset(name: filename)!.data)
           audioPlayer?.play()
       } catch {
           print("音楽ファイルの再生に失敗しました")
       }
   }
    
    func catchablelistChacker(Catchablelist:[Int]) {
        let list = Catchablelist
        for (i, catchable) in list.enumerated() {
            if catchable == 0 {
                switch i {
                case 0:
                    if (list[3] == -1 || list[1] == -1) && list[16] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 1:
                    if (list[0] == -1 || list[2] == -1) && list[17] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 4:
                    if (list[9] == -1 || list[5] == -1) && list[18] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 5:
                    if (list[4] == -1 || list[6] == -1) && list[19] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 8:
                    if list[11] == -1 || list[9] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 9:
                    if list[8] == -1 || list[10] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 12:
                    if list[15] == -1 || list[13] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 13:
                    if list[12] == -1 || list[14] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 16:
                    if list[20] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 18:
                    if list[20] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 17:
                    if list[21] == -1 {
                        self.catchablelist[i] = 1
                    }
                case 19:
                    if list[21] == -1 {
                        self.catchablelist[i] = 1
                    }
                default:
                    break
                }
            }
        }
    }
}





