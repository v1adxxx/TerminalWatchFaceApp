import SwiftUI
import HealthKit
import WatchKit

@main
struct TerminalWatchFaceApp: App {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            WatchFaceView()
        }
    }
}

struct WatchFaceView: View {
    private let healthStore = HKHealthStore()
    
    @State private var currentTime = getCurrentTime()
    @State private var currentDate = getCurrentDate()
    @State private var batteryLevel: String = "Loading..."
    @State private var stepsCount: String = "0 steps"
    @State private var heartRate: String = "0, u r dying"
    @State private var temperature: String = "Loading..."
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("user@watch:~ $ now")
                    .foregroundColor(.white)
                    .font(adaptiveFont())
                
                Group {
                    createTerminalLine(label: "[TIME]", value: currentTime, valueColor: .white)
                    createTerminalLine(label: "[DATE]", value: currentDate, valueColor: .blue)
                    createTerminalLine(label: "[BATT]", value: batteryLevel, valueColor: .green)
                    createTerminalLine(label: "[STEP]", value: stepsCount, valueColor: .cyan)
                    createTerminalLine(label: "[L_HR]", value: heartRate, valueColor: .red)
                    createTerminalLine(label: "[TEMP]", value: temperature, valueColor: .yellow)
                }
                
                Spacer()
                
                Text("user@watch:~ $")
                    .foregroundColor(.white)
                    .font(adaptiveFont())
            }
            .padding()
            .onAppear {
                fetchBatteryLevel()
                requestHealthData()
                fetchTemperature()
            }
            .onReceive(timer) { _ in
                self.currentTime = WatchFaceView.getCurrentTime()
                self.currentDate = WatchFaceView.getCurrentDate()
            }
        }
    }
    
    func createTerminalLine(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .font(adaptiveFont())
                .lineLimit(1)
            
            Text(value)
                .foregroundColor(valueColor)
                .font(adaptiveFont())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            
            Spacer()
        }
    }
    
    func adaptiveFont() -> Font {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        let size: CGFloat = screenWidth <= 200 ? 12 : 14
        return Font.system(size: size, weight: .medium, design: .monospaced)
    }
    
    func fetchBatteryLevel() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let level = WKInterfaceDevice.current().batteryLevel
        batteryLevel = String(format: "%.0f%%", level * 100)
    }
    
    func requestHealthData() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        
        let typesToShare: Set = [stepType]
        let typesToRead: Set = [stepType, heartRateType]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if success {
                fetchSteps()
                fetchHeartRate()
            }
        }
    }
    
    func fetchSteps() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let sum = result?.sumQuantity() else { return }
            DispatchQueue.main.async {
                self.stepsCount = String(format: "%.0f steps", sum.doubleValue(for: HKUnit.count()))
            }
        }
        healthStore.execute(query)
    }
    
    func fetchHeartRate() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, _ in
            guard let result = results?.first as? HKQuantitySample else { return }
            let heartRate = result.quantity.doubleValue(for: HKUnit(from: "count/min"))
            DispatchQueue.main.async {
                self.heartRate = String(format: "%.0f BPM", heartRate)
            }
        }
        healthStore.execute(query)
    }
    
    static func getCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm:ss a"
        return formatter.string(from: Date())
    }
    
    static func getCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, EEE"
        return formatter.string(from: Date())
    }
    
    func fetchTemperature() {
        let weatherAPIKey = "705b21b665264ed393603610250601"
        let weatherAPIURL = "https://api.weatherapi.com/v1/current.json"
        
        guard let url = URL(string: "\(weatherAPIURL)?key=\(weatherAPIKey)&q=auto:ip") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching weather data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let current = json["current"] as? [String: Any],
                   let tempC = current["temp_c"] as? Double {
                    DispatchQueue.main.async {
                        self.temperature = String(format: "%.1f°C", tempC)
                    }
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
            }
        }.resume()
    }
}
