import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    let categories = ["Movies", "TV Shows", "Music", "Live TV", "IPTV Movies", "IPTV Series", "Settings"]
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.07, green: 0.07, blue: 0.07)
                .ignoresSafeArea()
            
            // Sakura Accents
            SakuraPetalsView()
            
            NavigationView {
                HStack(spacing: 0) {
                    // Side Navigation
                    VStack(alignment: .leading, spacing: 30) {
                        Text("Lumina")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.77))
                            .padding(.bottom, 50)
                        
                        ForEach(0..<categories.count, id: \.self) { index in
                            Button(action: { selectedTab = index }) {
                                Text(categories[index])
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SakuraButtonStyle(isSelected: selectedTab == index))
                        }
                        
                        Spacer()
                    }
                    .frame(width: 400)
                    .padding(50)
                    .background(Color.black.opacity(0.3))
                    
                    // Main Content
                    VStack(alignment: .leading) {
                        Text(categories[selectedTab])
                            .font(.system(size: 80, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 20)
                        
                        ScrollView(.horizontal) {
                            HStack(spacing: 40) {
                                ForEach(0..<10) { _ in
                                    MediaCardView()
                                }
                            }
                            .padding(.bottom, 50)
                        }
                        
                        Spacer()
                    }
                    .padding(80)
                }
            }
        }
    }
}

struct SakuraButtonStyle: ButtonStyle {
    var isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(isSelected ? Color(red: 1.0, green: 0.72, blue: 0.77).opacity(0.8) : Color.clear)
            .cornerRadius(15)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .foregroundColor(isSelected ? .black : .white)
    }
}

struct MediaCardView: View {
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 400, height: 225)
                
                Text("Sakura Night Stream")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Live | AI Subtitles")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.77))
            }
        }
        .buttonStyle(.card)
    }
}

struct SakuraPetalsView: View {
    var body: some View {
        // Placeholder for falling flower animation
        Canvas { context, size in
            // Logic for drawing petals
        }
        .allowsHitTesting(false)
    }
}
