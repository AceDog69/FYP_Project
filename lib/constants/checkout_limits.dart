// Shared Cart/draft/receipt limits. Firestore Rules enforce the same bounds.
const maxCheckoutProducts = 2;
const maxCheckoutQuantity = 20;
const checkoutLimitsLabel = 'Up to two distinct foods per order, 1–20 units each.';
