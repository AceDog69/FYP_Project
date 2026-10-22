import 'package:flutter/foundation.dart';
import '../constants/checkout_limits.dart';
import '../models/confirmed_order.dart';
import 'auth_repository.dart';
import 'order_repository.dart';
import 'student_cart.dart';

/// Own one attempt for the whole authenticated Home, including route retries.
class CheckoutController extends ChangeNotifier {
  CheckoutController(this.cart, this.repository);
  final StudentCart cart;
  final OrderRepository? repository;
  CheckoutRequest? _request;
  int _cartVersion = 0;
  bool _clearMatchingCart = false, _active = true, _busy = false;
  String? error;
  CheckoutRequest? get request => _request;
  bool get busy => _busy;
  bool get enabled => repository?.canCheckout == true;

  void resume(CheckoutRequest saved) {
    if (!_active || saved.studentUid != cart.ownerUid) throw const AccountException('Your session changed.');
    if (saved.items.isEmpty || saved.items.length > maxCheckoutProducts) {
      throw const AccountException('Checkout supports one or two distinct foods.');
    }
    if (_request != null && _request!.id != saved.id) throw const AccountException('Resolve the open checkout first.');
    if (_request == null) {
      _request = saved; _cartVersion = cart.version; _clearMatchingCart = false;
      // Gated builds can review persisted drafts without freezing a usable
      // Cart behind a write operation that cannot currently be enabled.
      if (enabled) cart.lockCheckout(saved.id);
      notifyListeners();
    }
  }
  Future<OrderReceipt?> confirm(String paymentMethod) async {
    if (_busy) return null;
    if (!enabled) { error = 'Confirmation awaits executed security verification.'; notifyListeners(); return null; }
    if (!_active || !cart.active) throw const AccountException('Your checkout session ended.');
    if ((_request?.items.length ?? cart.lines.length) > maxCheckoutProducts) {
      error = 'Checkout supports at most two distinct foods.'; notifyListeners(); return null;
    }
    if (_request == null) {
      if (!cart.checkoutEligible) { error = 'Refresh and review your cart before checkout.'; notifyListeners(); return null; }
      final saved = CheckoutRequest(id: repository!.newSubmissionId(), studentUid: cart.ownerUid,
        vendorUid: cart.vendorId!, stallName: cart.stallName, paymentMethod: paymentMethod,
        items: cart.lines.map((l) => OrderItem(foodId: l.food.id, name: l.food.draft.name,
          description: l.food.draft.description, categoryId: l.food.draft.categoryId,
          pictureId: l.food.draft.pictureId, priceSen: l.food.draft.priceSen,
          quantity: l.quantity, foodRevision: l.food.revision)).toList());
      _request = saved; _cartVersion = cart.version; _clearMatchingCart = true; cart.lockCheckout(saved.id);
    }
    _busy = true; error = null; notifyListeners();
    try {
      final prepared = await repository!.prepare(_request!);
      if (!_active) return null;
      if (prepared.state == 'cancelled') {
        _release(clear: false); error = 'This unconfirmed request was discarded. Review the cart before retrying.'; return null;
      }
      _request = prepared;
      final receipt = await repository!.submit(prepared);
      if (!_active || !cart.active) return null;
      _release(clear: true); return receipt;
    } catch (e) {
      if (_active) error = orderError(e); // Same identity and Cart survive.
      return null;
    } finally {
      if (_active) { _busy = false; notifyListeners(); }
    }
  }
  Future<OrderReceipt?> discard() async {
    if (_busy || _request == null || !enabled) return null;
    _busy = true; error = null; notifyListeners();
    try {
      final receipt = await repository!.discard(_request!);
      if (!_active || !cart.active) return null;
      _release(clear: receipt != null);
      return receipt;
    } catch (e) { if (_active) error = orderError(e); return null; }
    finally { if (_active) { _busy = false; notifyListeners(); } }
  }
  void _release({required bool clear}) {
    cart.releaseCheckout(_request!.id, clearConfirmed: clear && _clearMatchingCart, expectedVersion: _cartVersion);
    _request = null; _clearMatchingCart = false;
  }
  @override
  void dispose() { _active = false; super.dispose(); }
}
