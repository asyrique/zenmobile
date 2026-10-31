import SwiftUI

/// Icons Skip can't draw on Android with `Image(systemName:)`: it maps only
/// some SF Symbols to Material icons and draws a warning sign for the rest.
/// These draw the SF Symbol on iOS and the matching Material icon on Android.
enum ZenSymbol: String {
    case desktop = "desktopcomputer"
    case pin = "pin.fill"
    case split = "rectangle.split.2x1"
    case spaces = "square.stack.3d.up"
    case privateTab = "eye.slash"
    case library = "books.vertical"
    case history = "clock"
}

struct ZenSymbolImage: View {
    let symbol: ZenSymbol
    /// The icon's size on Android, in points; on iOS the font sets it.
    var size: Double = 24

    var body: some View {
        #if os(Android)
        ComposeView {
            MaterialIconComposer(name: symbol.rawValue, size: size)
        }
        #else
        Image(systemName: symbol.rawValue)
        #endif
    }
}

#if SKIP
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.VerticalSplit
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

struct MaterialIconComposer : ContentComposer {
    let name: String
    let size: Double

    init(name: String, size: Double) {
        self.name = name
        self.size = size
    }

    @Composable func Compose(context: ComposeContext) {
        let icon: ImageVector
        switch name {
        case "desktopcomputer": icon = Icons.Outlined.Computer
        case "pin.fill": icon = Icons.Filled.PushPin
        case "rectangle.split.2x1": icon = Icons.Outlined.VerticalSplit
        case "square.stack.3d.up": icon = Icons.Outlined.Layers
        case "eye.slash": icon = Icons.Outlined.VisibilityOff
        case "books.vertical": icon = Icons.Outlined.CollectionsBookmark
        case "clock": icon = Icons.Outlined.History
        default: icon = Icons.Outlined.Warning
        }
        Icon(imageVector: icon, contentDescription: nil, modifier: context.modifier.size(size.dp), tint: LocalContentColor.current)
    }
}
#endif
