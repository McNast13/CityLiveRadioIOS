import SwiftUI

struct TopMenuView: View {
    var isListenAgainActive: Bool
    var onCityLive: () -> Void
    var onListenAgain: () -> Void
    var onContact: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onCityLive) {
                VStack(spacing: 4) {
                    Image(systemName: "music.note.house")
                        .font(.title2)
                    Text("Live")
                        .font(.caption2)
                }
            }
            Spacer()
            Button(action: onListenAgain) {
                VStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                    Text("Listen Again")
                        .font(.caption2)
                }
            }
            Spacer()
            Button(action: onContact) {
                VStack(spacing: 4) {
                    Image(systemName: "envelope")
                        .font(.title2)
                    Text("Contact")
                        .font(.caption2)
                }
            }
        }
        .foregroundColor(.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(VisualEffectBlur(blurStyle: .systemMaterial))
        .cornerRadius(12)
        .shadow(radius: 6)
        .padding(.horizontal, 12)
    }
}

// Small blur view helper for nice background
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct TopMenuView_Previews: PreviewProvider {
    static var previews: some View {
        TopMenuView(isListenAgainActive: false, onCityLive: {}, onListenAgain: {}, onContact: {})
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
