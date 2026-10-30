import type { Caption } from "@remotion/captions";
import { useCallback, useEffect, useState } from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  staticFile,
  useCurrentFrame,
  useDelayRender,
  useVideoConfig,
} from "remotion";
import { theme } from "./theme";

export const Captions: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const [captions, setCaptions] = useState<Caption[] | null>(null);
  const { delayRender, continueRender, cancelRender } = useDelayRender();
  const [handle] = useState(() => delayRender("Loading captions"));

  const load = useCallback(async () => {
    try {
      const response = await fetch(staticFile("audio/captions.json"));
      const data = (await response.json()) as Caption[];
      setCaptions(data);
      continueRender(handle);
    } catch (error) {
      cancelRender(error);
    }
  }, [cancelRender, continueRender, handle]);

  useEffect(() => {
    load();
  }, [load]);

  if (!captions) {
    return null;
  }

  const nowMs = (frame / fps) * 1000;
  const current = captions.find(
    (caption) => caption.startMs <= nowMs && caption.endMs > nowMs,
  );

  if (!current) {
    return null;
  }

  const localMs = nowMs - current.startMs;
  const durationMs = current.endMs - current.startMs;
  const opacity = interpolate(
    localMs,
    [0, 160, Math.max(200, durationMs - 180), durationMs],
    [0, 1, 1, 0],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.16, 1, 0.3, 1),
    },
  );

  return (
    <AbsoluteFill
      style={{
        justifyContent: "flex-end",
        alignItems: "center",
        padding: "0 110px 62px",
        pointerEvents: "none",
      }}
    >
      <div
        style={{
          opacity,
          maxWidth: 1540,
          border: `1px solid ${theme.line}`,
          borderRadius: 18,
          background: "rgba(4, 9, 15, 0.82)",
          boxShadow: "0 18px 60px rgba(0, 0, 0, 0.28)",
          color: theme.text,
          fontSize: 38,
          fontWeight: 650,
          lineHeight: 1.3,
          letterSpacing: "0.01em",
          padding: "17px 28px 19px",
          textAlign: "center",
        }}
      >
        {current.text}
      </div>
    </AbsoluteFill>
  );
};
