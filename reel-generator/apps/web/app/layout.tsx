import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Reel Generator",
  description: "Turn a topic into a faceless short-form video.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
