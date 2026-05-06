//
//  RowImage.swift
//  Castle
//
//  Renders a row's icon: the real Kingfisher-loaded image when a URL is present,
//  otherwise a `PlaceholderIcon` keyed off the row name. Single point of decision
//  so screenshot mode (preview store with no image URLs) renders consistently.
//

import Kingfisher
import SwiftUI

struct RowImage: View {
    let url: URL?
    let fallbackName: String
    var size: CGSize = CGSize(width: 44, height: 44)

    #if DEBUG
    /**
     Pass `-screenshotMode YES` in the scheme's run environment variables to put the app into a mode appropriate for taking App Store-ready screenshots. Notably, we don't display real icons, as doing so runs afoul of review rules around imitation.
     */
    let screenshotMode = ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    #else
    let screenshotMode: Bool = false
    #endif
    
    var body: some View {
        if !screenshotMode, let url {
            KFImage(url)
                .resizable()
                .frame(width: size.width, height: size.height)
        } else {
            PlaceholderIcon(name: fallbackName, size: size)
        }
    }
}
