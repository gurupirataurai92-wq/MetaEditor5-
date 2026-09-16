/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // @reel/core ships as TS-built ESM; transpile it through Next.
  transpilePackages: ["@reel/core"],
};

export default nextConfig;
