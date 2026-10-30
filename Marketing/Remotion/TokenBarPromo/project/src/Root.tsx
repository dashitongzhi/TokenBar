import "./index.css";
import { Composition } from "remotion";
import { PromoContent, PROMO_DURATION_FRAMES } from "./Promo";

export const TokenBarPromo: React.FC = () => <PromoContent />;

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="TokenBarPromo"
      component={TokenBarPromo}
      durationInFrames={PROMO_DURATION_FRAMES}
      fps={30}
      width={1920}
      height={1080}
      defaultProps={{}}
    />
  );
};
