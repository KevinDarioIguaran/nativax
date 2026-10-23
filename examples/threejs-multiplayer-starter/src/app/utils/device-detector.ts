/**
 * Device detection utilities for mobile/desktop UI switching
 */

/**
 * Check if device supports touch input
 */
export function isTouchDevice(): boolean {
  return (
    "ontouchstart" in window ||
    navigator.maxTouchPoints > 0 ||
    window.matchMedia("(pointer: coarse)").matches
  );
}

/**
 * Check if device should use mobile UI
 * Combines touch detection with screen size check
 */
export function isMobile(): boolean {
  return isTouchDevice() && window.innerWidth < 1024;
}
