export const QUALITY_PRESETS = {
  ultra: {
    label: '极致',
    pixelRatio: 2,
    shadowMapSize: 4096,
    shadowCascades: 3,
    ssao: true,
    bloom: true,
    colorGrade: true,
    vignette: true,
    fxaa: true,
    volumetricFog: true,
    clouds: true,
    particleScale: 1.35,
    decalLimit: 160,
    vegetationDensity: 1,
  },
  high: {
    label: '高',
    pixelRatio: 1.75,
    shadowMapSize: 2048,
    shadowCascades: 2,
    ssao: true,
    bloom: true,
    colorGrade: true,
    vignette: true,
    fxaa: true,
    volumetricFog: true,
    clouds: true,
    particleScale: 1,
    decalLimit: 100,
    vegetationDensity: 0.75,
  },
  medium: {
    label: '中',
    pixelRatio: 1.5,
    shadowMapSize: 1024,
    shadowCascades: 1,
    ssao: false,
    bloom: true,
    colorGrade: true,
    vignette: true,
    fxaa: true,
    volumetricFog: false,
    clouds: false,
    particleScale: 0.75,
    decalLimit: 60,
    vegetationDensity: 0.5,
  },
};

export const quality = {
  ...QUALITY_PRESETS.ultra,
  set(preset) {
    const next = QUALITY_PRESETS[preset] || QUALITY_PRESETS.ultra;
    Object.assign(this, next);
    this.preset = preset;
  },
};
