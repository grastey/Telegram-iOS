import org.telegram.messenger.GhostGramWalletMath;

public final class WalletTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    private static void rejects(Runnable action) {
        try { action.run(); } catch (IllegalArgumentException | ArithmeticException expected) { return; }
        throw new AssertionError("Invalid amount accepted");
    }
    public static void main(String[] args) {
        check(GhostGramWalletMath.parseStars("1000000000000") == 1_000_000_000_000L);
        check(GhostGramWalletMath.parseTon("0,000000001") == 1);
        check(GhostGramWalletMath.parseTon("1000000000") == 1_000_000_000_000_000_000L);
        rejects(() -> GhostGramWalletMath.parseStars("-1"));
        rejects(() -> GhostGramWalletMath.parseStars("1000000000001"));
        rejects(() -> GhostGramWalletMath.parseTon("1e3"));
        rejects(() -> GhostGramWalletMath.parseTon("1.0000000001"));
        rejects(() -> GhostGramWalletMath.parseTon("1000000000.000000001"));
        GhostGramWalletMath wallet = new GhostGramWalletMath(100_000, 100_000_000_000L);
        GhostGramWalletMath stars = wallet.spend(false, 15);
        check(stars.stars == 99_985 && stars.ton == wallet.ton);
        GhostGramWalletMath ton = stars.spend(true, 1);
        check(ton.ton == 99_999_999_999L && ton.stars == stars.stars);
        check(wallet.spend(false, Long.MAX_VALUE).stars == 0);
        check(wallet.spend(true, Long.MAX_VALUE).ton == 0);
        check(wallet.spend(false, -1).stars == wallet.stars);
        System.out.println("Exact local Stars/TON parsing, limits, independent currencies and spending passed");
    }
}
