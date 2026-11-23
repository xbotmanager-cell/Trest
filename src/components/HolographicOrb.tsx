import React, { useEffect, useRef } from 'react';

export type OrbStatus = 'idle' | 'listening' | 'thinking' | 'speaking' | 'error';

interface HolographicOrbProps {
  status: OrbStatus;
  audioLevel?: number;
  size?: number;
  onActivate?: () => void;
}

export const HolographicOrb: React.FC<HolographicOrbProps> = ({
  status,
  audioLevel = 0,
  size = 204,
  onActivate,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const levelRef = useRef(audioLevel);
  const statusRef = useRef(status);

  levelRef.current = audioLevel;
  statusRef.current = status;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = size * dpr;
    canvas.height = size * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    let rafId = 0;
    let phase = 0;
    let smoothedLevel = 0;

    const render = () => {
      const currentStatus = statusRef.current;
      const targetLevel = Math.max(0, Math.min(1, levelRef.current));
      smoothedLevel += (targetLevel - smoothedLevel) * 0.18;

      const speed =
        currentStatus === 'thinking'
          ? 0.048
          : currentStatus === 'speaking'
            ? 0.036 + smoothedLevel * 0.024
            : currentStatus === 'listening'
              ? 0.03 + smoothedLevel * 0.02
              : currentStatus === 'error'
                ? 0.012
                : 0.015;
      phase += speed;

      ctx.clearRect(0, 0, size, size);
      const cx = size / 2;
      const cy = size / 2;
      const maxR = size * 0.44;

      const [primary, secondary, tertiary] =
        currentStatus === 'error'
          ? ['#EF4444', '#F59E0B', '#EF4444']
          : currentStatus === 'thinking'
            ? ['#7C4DFF', '#2979FF', '#00E5FF']
            : ['#00E5FF', '#2979FF', '#7C4DFF'];

      const bloomAlpha =
        currentStatus === 'idle' ? 0.18 : 0.24 + smoothedLevel * 0.22;
      const bloom = ctx.createRadialGradient(cx, cy, 4, cx, cy, maxR * 1.1);
      bloom.addColorStop(0, `${primary}44`);
      bloom.addColorStop(0.5, `${secondary}22`);
      bloom.addColorStop(1, 'transparent');
      ctx.globalAlpha = bloomAlpha * 2.2;
      ctx.fillStyle = bloom;
      ctx.beginPath();
      ctx.arc(cx, cy, maxR * 1.1, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;

      // Glass orb base
      const disc = ctx.createRadialGradient(cx - maxR * 0.2, cy - maxR * 0.2, 4, cx, cy, maxR * 0.85);
      disc.addColorStop(0, 'rgba(22, 32, 68, 0.78)');
      disc.addColorStop(1, 'rgba(5, 8, 20, 0.94)');
      ctx.fillStyle = disc;
      ctx.beginPath();
      ctx.arc(cx, cy, maxR * 0.84, 0, Math.PI * 2);
      ctx.fill();

      // Rotating outer arc
      ctx.strokeStyle = primary;
      ctx.lineWidth = 2.6;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.arc(cx, cy, maxR * 0.92, phase, phase + Math.PI * 1.2);
      ctx.stroke();

      // 3 Internal harmonic sound-wave loops
      const intensity =
        currentStatus === 'idle'
          ? 0.16
          : currentStatus === 'thinking'
            ? 0.42
            : currentStatus === 'listening'
              ? 0.26 + smoothedLevel * 0.74
              : currentStatus === 'speaking'
                ? 0.34 + smoothedLevel * 0.66
                : 0.12;

      const waves = [
        { radius: maxR * 0.68, amp: maxR * 0.11 * intensity, freq: 5, shift: phase, width: 2.3, color: primary },
        { radius: maxR * 0.58, amp: maxR * 0.1 * intensity, freq: 7, shift: -phase * 1.25 + 1.1, width: 1.8, color: secondary },
        { radius: maxR * 0.48, amp: maxR * 0.08 * intensity, freq: 3, shift: phase * 1.6 + 2.2, width: 1.4, color: tertiary },
      ];

      for (const wave of waves) {
        ctx.strokeStyle = wave.color;
        ctx.lineWidth = wave.width;
        ctx.beginPath();
        const steps = 72;
        for (let i = 0; i <= steps; i++) {
          const theta = (i / steps) * Math.PI * 2;
          const mod =
            0.68 * Math.sin(theta * wave.freq + wave.shift) +
            0.32 * Math.cos(theta * (wave.freq - 2) - wave.shift * 0.7);
          const r = wave.radius + wave.amp * mod;
          const x = cx + Math.cos(theta) * r;
          const y = cy + Math.sin(theta) * r;
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.closePath();
        ctx.stroke();
      }

      // Inner D core silhouette
      const dScale = maxR * 0.34;
      ctx.strokeStyle = primary;
      ctx.lineWidth = 3.2;
      ctx.lineJoin = 'round';
      ctx.beginPath();
      ctx.moveTo(cx - dScale * 0.52, cy - dScale * 0.6);
      ctx.lineTo(cx, cy - dScale * 0.6);
      ctx.bezierCurveTo(
        cx + dScale * 0.72,
        cy - dScale * 0.6,
        cx + dScale * 0.72,
        cy + dScale * 0.6,
        cx,
        cy + dScale * 0.6,
      );
      ctx.lineTo(cx - dScale * 0.52, cy + dScale * 0.6);
      ctx.closePath();
      ctx.stroke();

      rafId = requestAnimationFrame(render);
    };

    rafId = requestAnimationFrame(render);
    return () => cancelAnimationFrame(rafId);
  }, [size]);

  return (
    <button
      type="button"
      onClick={onActivate}
      aria-label={`Dane holographic voice orb, status ${status}`}
      style={{ width: size, height: size }}
      className="relative inline-flex items-center justify-center rounded-full cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400 transition-transform duration-200 active:scale-95"
    >
      <canvas ref={canvasRef} style={{ width: size, height: size }} />
    </button>
  );
};
