// Settings.js — tunable global constants for feel/camera/persistence.

export const Settings = {
  // Camera & FOV
  baseFov: 78,
  sprintFov: 88,
  dashFov: 100,
  heavyHitFov: 92,
  fovLerp: 8,           // how fast FOV eases toward target

  // Look sensitivity (radians per pixel of mouse movement)
  lookSensitivity: 0.0022,
  pitchClamp: Math.PI / 2 - 0.05,

  // Movement
  gravity: -26,
  jumpForce: 9.5,
  groundFriction: 12,
  airControl: 0.35,

  // Combat windows (ms)
  parryWindowMs: 200,   // tap F within this for a perfect parry
  comboResetMs: 900,    // time before the M1 combo counter resets
  blockDamageReduction: 0.8,

  // Persistence
  saveKey: 'soulrift:save:v1',
};

export default Settings;
