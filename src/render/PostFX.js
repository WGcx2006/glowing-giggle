import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { SSAOPass } from 'three/examples/jsm/postprocessing/SSAOPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { FXAAShader } from 'three/examples/jsm/shaders/FXAAShader.js';

const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uTint: { value: new THREE.Color(1, 1, 1) },
    uSaturation: { value: 1 },
    uContrast: { value: 1 },
    uVignette: { value: 0.3 },
    uGrain: { value: 0.01 },
  },
  vertexShader: `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: `
    uniform sampler2D tDiffuse;
    uniform float uTime;
    uniform vec3 uTint;
    uniform float uSaturation;
    uniform float uContrast;
    uniform float uVignette;
    uniform float uGrain;
    varying vec2 vUv;

    float hash(vec2 p) {
      return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
    }

    void main() {
      vec4 color = texture2D(tDiffuse, vUv);
      vec3 c = color.rgb;
      float luma = dot(c, vec3(0.299, 0.587, 0.114));
      c = mix(vec3(luma), c, uSaturation);
      c = (c - 0.5) * uContrast + 0.5;
      c *= uTint;

      vec2 centered = vUv - 0.5;
      float radius = length(centered);
      float vig = 1.0 - smoothstep(0.34, 0.92, radius * (1.0 + uVignette));
      c *= mix(1.0, vig, uVignette);

      float grain = hash(gl_FragCoord.xy + fract(uTime) * 137.0);
      c += (grain - 0.5) * uGrain;
      c = max(c, 0.0);
      gl_FragColor = vec4(c, color.a);
    }
  `,
};

export class PostFX {
  constructor(renderer, scene, camera, quality = {}) {
    this.renderer = renderer;
    this.scene = scene;
    this.camera = camera;
    this.quality = quality;
    this.time = 0;

    const w = renderer.domElement.width || window.innerWidth;
    const h = renderer.domElement.height || window.innerHeight;
    const pixelRatio = Math.min(renderer.getPixelRatio() || 1, quality.pixelRatio || 2);
    this.composer = new EffectComposer(renderer);
    this.composer.setPixelRatio(pixelRatio);
    this.composer.setSize(w, h);

    this.renderPass = new RenderPass(scene, camera);
    this.composer.addPass(this.renderPass);

    if (quality.ssao !== false) {
      this.ssaoPass = new SSAOPass(scene, camera, w, h);
      this.ssaoPass.output = SSAOPass.OUTPUT.Default;
      this.composer.addPass(this.ssaoPass);
    }

    if (quality.bloom !== false) {
      this.bloomPass = new UnrealBloomPass(new THREE.Vector2(w, h), 0.42, 0.72, 0.82);
      this.composer.addPass(this.bloomPass);
    }

    if (quality.colorGrade !== false || quality.vignette !== false) {
      this.gradePass = new ShaderPass(GradeShader);
      this.composer.addPass(this.gradePass);
    }

    if (quality.fxaa !== false) {
      this.fxaaPass = new ShaderPass(FXAAShader);
      this.fxaaPass.uniforms.resolution.value.set(1 / (w * pixelRatio), 1 / (h * pixelRatio));
      this.composer.addPass(this.fxaaPass);
    }

    this.outputPass = new OutputPass();
    this.composer.addPass(this.outputPass);
  }

  render(dt = 0) {
    this.time += dt || 0;
    const state = this.scene.userData?.post;
    if (state) {
      if (typeof state.exposure === 'number') this.renderer.toneMappingExposure = state.exposure;
      if (this.gradePass) {
        const uniforms = this.gradePass.uniforms;
        if (state.tint) uniforms.uTint.value.setRGB(state.tint[0], state.tint[1], state.tint[2]);
        uniforms.uSaturation.value = state.saturation ?? 1;
        uniforms.uContrast.value = state.contrast ?? 1;
        uniforms.uVignette.value = Math.min(0.36, state.vignette ?? 0.3);
        uniforms.uGrain.value = Math.min(0.02, state.grain ?? 0.01);
        uniforms.uTime.value = this.time;
      }
    }
    this.composer.render(dt);
  }

  resize(w, h) {
    const pixelRatio = Math.min(this.renderer.getPixelRatio() || 1, this.quality.pixelRatio || 2);
    this.composer.setPixelRatio(pixelRatio);
    this.composer.setSize(w, h);
    this.ssaoPass?.setSize(w, h);
    this.bloomPass?.setSize(w, h);
    if (this.fxaaPass) {
      this.fxaaPass.uniforms.resolution.value.set(1 / (w * pixelRatio), 1 / (h * pixelRatio));
    }
  }
}
