import Link from 'next/link'

const footerLinks = {
  blog: [
    { label: 'What is vTVL?', href: '#' },
    { label: 'SLAC Explained', href: '#' },
    { label: 'Volume-To-TVL Ratio', href: '#' },
  ],
  docs: [
    { label: 'Read the docs', href: '#' },
  ],
  legal: [
    { label: 'Terms & conditions', href: '#' },
    { label: 'Privacy Policy', href: '#' },
  ],
}

export function Footer() {
  return (
    <footer className="bg-background px-4 py-8 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-7xl">
        <div className="rounded-2xl bg-secondary/50 px-8 py-10 md:px-12 md:py-12">
          <div className="grid grid-cols-2 gap-8 md:grid-cols-4">
            {/* Brand */}
            <div className="col-span-2 md:col-span-1">
              <h2 className="text-xl font-bold tracking-tight">AQUA0</h2>
              <p className="mt-3 text-sm text-muted-foreground leading-relaxed">
                The first cross-chain shared liquidity protocol
              </p>
            </div>

            {/* Blog Links */}
            <div>
              <h3 className="font-semibold">Blog</h3>
              <ul className="mt-4 space-y-3">
                {footerLinks.blog.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>

            {/* Docs Links */}
            <div>
              <h3 className="font-semibold">Docs</h3>
              <ul className="mt-4 space-y-3">
                {footerLinks.docs.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>

            {/* Legal Links */}
            <div>
              <h3 className="font-semibold">Legal</h3>
              <ul className="mt-4 space-y-3">
                {footerLinks.legal.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </div>
    </footer>
  )
}
