/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
    remotePatterns: [
      {
        protocol: "https",
        hostname: "coin-images.coingecko.com",
      },
    ],
  },
  /**
   * `pino` and `thread-stream` (pulled in via WalletConnect → Privy)
   * ship test files that reference dev-only modules. Keep them external
   * so the server-component bundler doesn't try to resolve those files.
   *
   * The main fix for the Client Component SSR path is the context split:
   * `wallet-context.tsx` (pure React, safe for SSR) vs
   * `wallet-provider.tsx` (Privy-heavy, loaded client-only via dynamic()).
   */
  serverExternalPackages: ["pino", "thread-stream"],
};

export default nextConfig;
