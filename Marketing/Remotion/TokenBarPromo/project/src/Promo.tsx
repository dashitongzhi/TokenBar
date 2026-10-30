import {
  ArrowCircleRight,
  CheckCircle,
  CloudArrowDown,
  GitBranch,
  HardDrives,
  ShieldCheck,
  WarningCircle,
  XCircle,
} from "@phosphor-icons/react";
import { Audio } from "@remotion/media";
import type { ReactNode } from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Captions } from "./Captions";
import { theme } from "./theme";

const ease = Easing.bezier(0.16, 1, 0.3, 1);

const fadeForScene = (frame: number, duration: number) =>
  interpolate(frame, [0, 16, duration - 18, duration], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: ease,
  });

const AmbientBackground: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const drift = interpolate(frame, [0, durationInFrames], [-60, 80]);

  return (
    <AbsoluteFill style={{ background: theme.bg, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(circle at 18% 18%, rgba(34,186,244,0.15), transparent 34%), radial-gradient(circle at 80% 78%, rgba(68,223,170,0.11), transparent 30%), linear-gradient(135deg, #05090f 0%, #08111c 55%, #05090f 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: -160,
          translate: `${drift}px ${-drift * 0.35}px`,
          opacity: 0.24,
          backgroundImage:
            "linear-gradient(rgba(122,184,219,0.08) 1px, transparent 1px), linear-gradient(90deg, rgba(122,184,219,0.08) 1px, transparent 1px)",
          backgroundSize: "96px 96px",
          maskImage:
            "radial-gradient(circle at center, black 0%, rgba(0,0,0,0.55) 42%, transparent 74%)",
        }}
      />
    </AbsoluteFill>
  );
};

const SceneFrame: React.FC<{
  duration: number;
  children: ReactNode;
}> = ({ duration, children }) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        opacity: fadeForScene(frame, duration),
        padding: "110px 120px 170px",
      }}
    >
      {children}
    </AbsoluteFill>
  );
};

const TextBlock: React.FC<{
  kicker?: string;
  title: string;
  body?: string;
  align?: "left" | "center";
  titleSize?: number;
}> = ({ kicker, title, body, align = "left", titleSize = 92 }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [4, 22], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: ease,
  });
  const translateY = interpolate(frame, [4, 24], [32, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: ease,
  });

  return (
    <div
      style={{
        opacity,
        translate: `0 ${translateY}px`,
        maxWidth: 980,
        textAlign: align,
      }}
    >
      {kicker ? (
        <div
          style={{
            color: theme.mint,
            fontSize: 27,
            fontWeight: 650,
            letterSpacing: "0.06em",
            marginBottom: 18,
          }}
        >
          {kicker}
        </div>
      ) : null}
      <div
        style={{
          color: theme.text,
          fontSize: titleSize,
          fontWeight: 760,
          letterSpacing: "-0.045em",
          lineHeight: 1.04,
          whiteSpace: "pre-line",
        }}
      >
        {title}
      </div>
      {body ? (
        <div
          style={{
            color: theme.muted,
            fontSize: 38,
            fontWeight: 480,
            lineHeight: 1.42,
            marginTop: 24,
            maxWidth: 880,
          }}
        >
          {body}
        </div>
      ) : null}
    </div>
  );
};

const ScreenshotPanel: React.FC<{
  src: string;
  frame: number;
  objectPosition?: string;
}> = ({ src, frame, objectPosition = "center" }) => {
  const scale = interpolate(frame, [0, 180], [1.045, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: ease,
  });
  const translateY = interpolate(frame, [0, 24], [34, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: ease,
  });

  return (
    <div
      style={{
        overflow: "hidden",
        borderRadius: 34,
        border: "1px solid rgba(163, 213, 238, 0.22)",
        background: "#05090f",
        boxShadow:
          "0 44px 120px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.1)",
        height: 700,
        opacity: interpolate(frame, [0, 18], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: ease,
        }),
        translate: `0 ${translateY}px`,
      }}
    >
      <Img
        src={staticFile(src)}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          objectPosition,
          scale,
        }}
      />
    </div>
  );
};

const ImagePlate: React.FC<{ src: string; frame: number }> = ({ src, frame }) => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      overflow: "hidden",
      opacity: interpolate(frame, [0, 24], [0, 0.74], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
        easing: ease,
      }),
    }}
  >
    <Img
      src={staticFile(src)}
      style={{
        width: "100%",
        height: "100%",
        objectFit: "cover",
        scale: interpolate(frame, [0, 320], [1.09, 1.01], {
          extrapolateRight: "clamp",
          easing: ease,
        }),
      }}
    />
    <div
      style={{
        position: "absolute",
        inset: 0,
        background:
          "linear-gradient(90deg, rgba(5,9,15,0.98) 0%, rgba(5,9,15,0.82) 44%, rgba(5,9,15,0.2) 78%), linear-gradient(0deg, rgba(5,9,15,0.88), transparent 48%)",
      }}
    />
  </div>
);

const ProblemScene: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const terms = ["错误工作区", "失控预算", "不合规模型"];

  return (
    <SceneFrame duration={duration}>
      <div style={{ display: "flex", height: "100%", alignItems: "center" }}>
        <div style={{ flex: 1 }}>
          <TextBlock
            kicker="AI AGENT 正在加速"
            title="执行更快，风险也更快"
            body="一次错误判断，几秒内就会触碰仓库、额度与真实成本。"
          />
        </div>
        <div
          style={{
            width: 540,
            display: "flex",
            flexDirection: "column",
            gap: 18,
          }}
        >
          {terms.map((term, index) => (
            <div
              key={term}
              style={{
                opacity: interpolate(frame, [22 + index * 10, 40 + index * 10], [0, 1], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: ease,
                }),
                translate: `${interpolate(frame, [22 + index * 10, 42 + index * 10], [56, 0], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: ease,
                })}px 0`,
                borderTop: `1px solid ${theme.line}`,
                padding: "24px 0",
                color: index === 1 ? theme.amber : theme.muted,
                fontSize: 43,
                fontWeight: 650,
              }}
            >
              {term}
            </div>
          ))}
        </div>
      </div>
    </SceneFrame>
  );
};

const BrandScene: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  return (
    <SceneFrame duration={duration}>
      <div
        style={{
          display: "flex",
          height: "100%",
          alignItems: "center",
          justifyContent: "center",
          gap: 52,
        }}
      >
        <Img
          src={staticFile("brand/tokenbar-icon.png")}
          style={{
            width: 270,
            height: 270,
            borderRadius: 58,
            opacity: interpolate(frame, [0, 18], [0, 1], {
              extrapolateRight: "clamp",
              easing: ease,
            }),
            scale: interpolate(frame, [0, 22], [0.84, 1], {
              extrapolateRight: "clamp",
              easing: ease,
            }),
            boxShadow: "0 32px 90px rgba(0,0,0,0.55)",
          }}
        />
        <TextBlock
          title="TokenBar"
          body="macOS 上面向 AI 编程代理的本地策略闸门。"
        />
      </div>
    </SceneFrame>
  );
};

const DecisionScene: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const decisions = [
    { label: "ALLOW", color: theme.green, icon: CheckCircle },
    { label: "WARN", color: theme.amber, icon: WarningCircle },
    { label: "BLOCK", color: theme.red, icon: XCircle },
  ];
  return (
    <SceneFrame duration={duration}>
      <ImagePlate src="generated/local-shield.png" frame={frame} />
      <div
        style={{
          position: "relative",
          zIndex: 1,
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
        }}
      >
        <TextBlock
          kicker="运行前决策"
          title="先检查，再执行。"
          body="工作区、供应商、模型、公司 Key、单次成本与预算投影，一次完成。"
        />
        <div style={{ display: "flex", gap: 22, marginTop: 54 }}>
          {decisions.map((decision, index) => {
            const Icon = decision.icon;
            return (
              <div
                key={decision.label}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 13,
                  color: decision.color,
                  fontSize: 38,
                  fontWeight: 760,
                  opacity: interpolate(frame, [44 + index * 16, 62 + index * 16], [0, 1], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                    easing: ease,
                  }),
                  translate: `0 ${interpolate(frame, [44 + index * 16, 64 + index * 16], [22, 0], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                    easing: ease,
                  })}px`,
                }}
              >
                <Icon size={44} weight="fill" />
                {decision.label}
              </div>
            );
          })}
        </div>
      </div>
    </SceneFrame>
  );
};

const ProductScene: React.FC<{
  duration: number;
  kicker: string;
  title: string;
  body: string;
  screenshot: string;
  objectPosition?: string;
}> = ({ duration, kicker, title, body, screenshot, objectPosition }) => {
  const frame = useCurrentFrame();
  return (
    <SceneFrame duration={duration}>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "0.72fr 1.28fr",
          gap: 64,
          height: "100%",
          alignItems: "center",
        }}
      >
        <TextBlock kicker={kicker} title={title} body={body} titleSize={78} />
        <ScreenshotPanel
          src={`screenshots/${screenshot}`}
          frame={frame}
          objectPosition={objectPosition}
        />
      </div>
    </SceneFrame>
  );
};

const LocalFirstScene: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const facts = [
    { icon: HardDrives, label: "本地优先" },
    { icon: GitBranch, label: "127.0.0.1" },
    { icon: CloudArrowDown, label: "缺失数据不记为零" },
  ];
  return (
    <SceneFrame duration={duration}>
      <ImagePlate src="generated/usage-convergence.png" frame={frame} />
      <div
        style={{
          position: "relative",
          zIndex: 1,
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
        }}
      >
        <TextBlock
          kicker="LOCAL FIRST"
          title="数据留在本机。判断保持诚实。"
          body="本地 API 只监听 loopback。未知就是未知，不会被包装成零成本。"
        />
        <div style={{ display: "flex", gap: 38, marginTop: 52 }}>
          {facts.map((fact, index) => {
            const Icon = fact.icon;
            return (
              <div
                key={fact.label}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 14,
                  color: theme.text,
                  fontSize: 31,
                  fontWeight: 620,
                  opacity: interpolate(frame, [34 + index * 13, 52 + index * 13], [0, 1], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                    easing: ease,
                  }),
                }}
              >
                <Icon size={39} color={theme.mint} weight="duotone" />
                {fact.label}
              </div>
            );
          })}
        </div>
      </div>
    </SceneFrame>
  );
};

const OutroScene: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  return (
    <SceneFrame duration={duration}>
      <div
        style={{
          display: "flex",
          height: "100%",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
        }}
      >
        <Img
          src={staticFile("brand/tokenbar-icon.png")}
          style={{
            width: 218,
            height: 218,
            borderRadius: 48,
            scale: interpolate(frame, [0, 24], [0.86, 1], {
              extrapolateRight: "clamp",
              easing: ease,
            }),
            boxShadow: "0 34px 100px rgba(0,0,0,0.52)",
          }}
        />
        <div
          style={{
            color: theme.text,
            fontSize: 94,
            fontWeight: 780,
            letterSpacing: "-0.05em",
            marginTop: 35,
          }}
        >
          TokenBar
        </div>
        <div
          style={{
            color: theme.muted,
            fontSize: 42,
            lineHeight: 1.4,
            marginTop: 20,
          }}
        >
          为每次 Agent 运行，给出清晰结论
        </div>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 13,
            color: theme.mint,
            fontSize: 34,
            fontWeight: 650,
            marginTop: 44,
            opacity: interpolate(frame, [32, 52], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: ease,
            }),
          }}
        >
          <ShieldCheck size={44} weight="duotone" />
          先过策略，再开始执行
          <ArrowCircleRight size={42} weight="duotone" />
        </div>
      </div>
    </SceneFrame>
  );
};

const fps = 30;
const scenes = [
  { start: 0, end: 282 },
  { start: 282, end: 411 },
  { start: 411, end: 803 },
  { start: 803, end: 1052 },
  { start: 1052, end: 1321 },
  { start: 1321, end: 1637 },
  { start: 1637, end: 1848 },
  { start: 1848, end: 2113 },
  { start: 2113, end: 2400 },
];

export const PromoContent: React.FC = () => (
  <AbsoluteFill>
    <AmbientBackground />
    <Sequence from={scenes[0].start} durationInFrames={scenes[0].end - scenes[0].start}>
      <ProblemScene duration={scenes[0].end - scenes[0].start} />
    </Sequence>
    <Sequence from={scenes[1].start} durationInFrames={scenes[1].end - scenes[1].start}>
      <BrandScene duration={scenes[1].end - scenes[1].start} />
    </Sequence>
    <Sequence from={scenes[2].start} durationInFrames={scenes[2].end - scenes[2].start}>
      <DecisionScene duration={scenes[2].end - scenes[2].start} />
    </Sequence>
    <Sequence from={scenes[3].start} durationInFrames={scenes[3].end - scenes[3].start}>
      <ProductScene
        duration={scenes[3].end - scenes[3].start}
        kicker="GUARD"
        title="每次运行，都有可解释的结论"
        body="当前决定、策略原因、预计花费和回退方案，一眼看清。"
        screenshot="guard.png"
      />
    </Sequence>
    <Sequence from={scenes[4].start} durationInFrames={scenes[4].end - scenes[4].start}>
      <ProductScene
        duration={scenes[4].end - scenes[4].start}
        kicker="USAGE"
        title={"多平台用量\n集中查看"}
        body="实时额度、本地代理用量与健康状态，汇总到同一个真实界面。"
        screenshot="summary.png"
        objectPosition="50% 24%"
      />
    </Sequence>
    <Sequence from={scenes[5].start} durationInFrames={scenes[5].end - scenes[5].start}>
      <ProductScene
        duration={scenes[5].end - scenes[5].start}
        kicker="WORKSPACE POLICY"
        title="策略跟着仓库走"
        body="允许的供应商、首选模型、单次上限、日预算与月预算，都能独立配置。"
        screenshot="workspaces.png"
      />
    </Sequence>
    <Sequence from={scenes[6].start} durationInFrames={scenes[6].end - scenes[6].start}>
      <ProductScene
        duration={scenes[6].end - scenes[6].start}
        kicker="ONE POLICY ENGINE"
        title={"CLI、Hooks、\n本地 API\n一套引擎"}
        body="Codex、Claude Code 与自动化脚本，获得一致的运行前判断。"
        screenshot="integrations.png"
      />
    </Sequence>
    <Sequence from={scenes[7].start} durationInFrames={scenes[7].end - scenes[7].start}>
      <LocalFirstScene duration={scenes[7].end - scenes[7].start} />
    </Sequence>
    <Sequence from={scenes[8].start} durationInFrames={scenes[8].end - scenes[8].start}>
      <OutroScene duration={scenes[8].end - scenes[8].start} />
    </Sequence>
    <Audio src={staticFile("audio/narration.mp3")} volume={1} />
    <Captions />
  </AbsoluteFill>
);

export const PROMO_DURATION_FRAMES = 80 * fps;
