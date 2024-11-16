import Foundation

class TokenBalanceManager: ObservableObject {
    static let shared = TokenBalanceManager()
    
    @Published var balance: String = "0"
    private var isRefreshing = false
    
    private init() {}
    
    func refreshBalance() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        do {
            let (_, testBalance) = try await EthereumManager.shared.getBalances()
            await MainActor.run {
                self.balance = testBalance.components(separatedBy: ".")[0]
                self.isRefreshing = false
            }
        } catch {
            print("Error fetching balance: \(error)")
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }
} 