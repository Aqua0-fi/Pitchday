import type React from "react"
import type { Metadata } from "next"
import { Space_Grotesk } from "next/font/google"
import { Analytics } from "@vercel/analytics/next"
import { Toaster } from "@/components/ui/toaster"
import { ClientProviders } from "@/components/client-providers"
import "./globals.css"

const spaceGrotesk = Space_Grotesk({
  subsets: ["latin"],
  variable: "--font-space-grotesk",
})

export const metadata: Metadata = {
  title: "AQUA0 - Cross-Chain DeFi Protocol",
  description: "Deploy liquidity across multiple chains with optimized strategies. Swap tokens cross-chain with the best rates.",
  generator: "v0.app",
  icons: {
    icon: "/favicon-32x32.png",
    apple: "/favicon-32x32.png",
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en">
      <body className={`${spaceGrotesk.variable} font-sans antialiased`}>
        <ClientProviders>
          <div className="flex min-h-screen flex-col">
            <main className="flex-1">{children}</main>
          </div>
          <Toaster />
        </ClientProviders>
        <Analytics />
      </body>
    </html>
  )
}
