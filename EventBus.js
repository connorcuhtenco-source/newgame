// EventBus.js — tiny global pub/sub used to decouple systems.
// Systems emit events (e.g. "player:levelup") without knowing who listens.
// This keeps Combat, Progression, UI, Audio and VFX loosely coupled.

class EventBus {
  constructor() {
    this._listeners = new Map();
  }

  on(event, handler) {
    if (!this._listeners.has(event)) this._listeners.set(event, new Set());
    this._listeners.get(event).add(handler);
    return () => this.off(event, handler);
  }

  once(event, handler) {
    const wrapped = (payload) => {
      this.off(event, wrapped);
      handler(payload);
    };
    return this.on(event, wrapped);
  }

  off(event, handler) {
    const set = this._listeners.get(event);
    if (set) set.delete(handler);
  }

  emit(event, payload) {
    const set = this._listeners.get(event);
    if (!set) return;
    // Copy to allow handlers to unsubscribe during dispatch.
    for (const handler of [...set]) {
      try {
        handler(payload);
      } catch (err) {
        console.error(`[EventBus] handler for "${event}" threw:`, err);
      }
    }
  }
}

// Single shared instance — the game's nervous system.
export const Events = new EventBus();
export default Events;
