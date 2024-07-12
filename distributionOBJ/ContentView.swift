//
//  ContentView.swift
//  distributionOBJ
//
//  Created by 徳田泰地 on 2024/06/18.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HandInteractionARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct HandInteractionARViewContainer: UIViewControllerRepresentable {
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<HandInteractionARViewContainer>) -> distributionOBJController {

        let viewController = distributionOBJController()
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: distributionOBJController, context: UIViewControllerRepresentableContext<HandInteractionARViewContainer>) {
        //SwiftUIViewが更新された時に呼び出される関数,画面の更新
    }
    
    func makeCoordinator() -> HandInteractionARViewContainer.Coordinator {
        return Coordinator()
    }
    
    class Coordinator {
        
    }
}
