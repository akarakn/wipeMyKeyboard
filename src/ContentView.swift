import SwiftUI

struct ContentView: View {
    @StateObject private var locker = KeyboardLocker()
    
    var body: some View {
        VStack(spacing: 20) {
            if !locker.isAccessibilityEnabled && !locker.isLocked {
                Text("Accessibility Permissions Required")
                    .foregroundColor(.red)
                    .font(.headline)
                Text("from System Settings > Privacy & Security > Accessibility.")
                    .multilineTextAlignment(.center)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            if locker.isLocked {
                Text("Keyboard Locked")
                    .font(.largeTitle)
                    .bold()
                
                Text("\(locker.timeRemaining)s")
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundColor(locker.timeRemaining <= 5 ? .red : .primary)
                
                Button("Unlock") {
                    locker.stopLocking()
                }
                .padding(.top)
            } else {
                Text("Wipe My Keyboard")
                    .font(.title)
                    .bold()
                
                VStack {
                    Text("Duration: \(Int(locker.duration)) seconds")
                    Slider(value: $locker.duration, in: 10...120, step: 10)
                        .padding(.horizontal)
                }
                
                Button(action: {
                    locker.startLocking()
                }) {
                    Text("Lock Keyboard")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}
