import 'dart:async';

/// Abstraction over the ad SDK so the UI does not depend on a specific
/// provider. Swap [MockAdService] for a real implementation (AdMob, AppLovin,
/// etc.) without touching call sites.
abstract class AdService {
  Future<bool> showRewardedAd({required String rewardType});
  Future<void> showInterstitial();
}

class MockAdService implements AdService {
  @override
  Future<bool> showRewardedAd({required String rewardType}) async {
    // Simulate a 2-second rewarded ad. Replace with real SDK call.
    await Future.delayed(const Duration(seconds: 2));
    return true;
  }

  @override
  Future<void> showInterstitial() async {
    // Simulate a 2-second interstitial. Replace with real SDK call.
    await Future.delayed(const Duration(seconds: 2));
  }
}

final AdService adService = MockAdService();