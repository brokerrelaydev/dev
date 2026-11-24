#!/usr/bin/env python3
"""Apply reviewed BrokerRelay CSV dashboard visibility changes to development source.
Fails before writing if any expected source text differs; does not touch Supabase.
"""
from pathlib import Path
from difflib import unified_diff

root = Path.cwd()
changes = {}

def replace(path, old, new):
    file = root / path
    source = changes.get(file, file.read_text(encoding='utf-8'))
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:100]!r}')
    changes[file] = source.replace(old, new, 1)

p='app/dashboard/page.tsx'
replace(p,"import { Fragment, useEffect, useState } from 'react'", "import { Fragment, useEffect, useState, type CSSProperties } from 'react'")
replace(p,"  lastName: string\n}\n\ntype ClientRow", """  lastName: string
  companyLinkColor: string
}

// Reuse the company's configured button colour only when readable on white.
function accessibleCompanyLinkColor(value: string | null | undefined): string {
  if (!value || !/^#[0-9a-fA-F]{6}$/.test(value)) return '#1d4ed8'
  const channels = [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16) / 255)
    .map(n => n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4)
  const luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
  return 1.05 / (luminance + 0.05) >= 4.5 ? value : '#1d4ed8'
}

type ClientRow""")
replace(p,"  connected_at: string | null\n}\n\ntype SecurityAction", "  connected_at: string | null\n  created_at: string\n}\n\ntype SecurityAction")
replace(p,".select('name,logo_url,logo_display_width,logo_display_height')", ".select('name,logo_url,logo_display_width,logo_display_height,mobile_button_color')")
replace(p,"      lastName: profile?.last_name ?? '',", "      lastName: profile?.last_name ?? '',\n      companyLinkColor: accessibleCompanyLinkColor(org?.mobile_button_color),")
replace(p,".select('id,first_name,last_name,email,mobile,status,connected_at')", ".select('id,first_name,last_name,email,mobile,status,connected_at,created_at')")
replace(p,"      .not('connected_at', 'is', null)\n      .order('connected_at', { ascending: false })", "      .order('created_at', { ascending: false })")
replace(p,"  const unreadTotal = Object.values(unread).reduce((total, count) => total + count, 0)", "  const unreadTotal = Object.values(unread).reduce((total, count) => total + count, 0)\n  const connectedCount = clients.filter(c => Boolean(c.connected_at)).length")
replace(p,'<main className="brokerDeskShell" id="home">','<main className="brokerDeskShell" id="home" style={{\'--broker-company-link\': context?.companyLinkColor ?? \'#1d4ed8\'} as CSSProperties}>')
replace(p,'<strong>{clients.length}</strong><small>Connected clients</small>', '<strong>{connectedCount}</strong><small>Connected clients</small>')
replace(p,'<h2>Recent connected clients</h2><Link href="/clients">View all clients →</Link>', """<h2>Recent clients</h2>
            <div className="brokerDeskClientActions">
              <Link className="brokerDeskClientAction" href="/clients">View all clients</Link>
              <Link className="brokerDeskClientAction" href="/clients/import">Import existing clients (CSV)</Link>
            </div>""")
replace(p,"<small>Connected {c.connected_at ? new Date(c.connected_at).toLocaleDateString('en-AU') : '—'}</small>", "<small>{c.connected_at ? 'Connected '+new Date(c.connected_at).toLocaleDateString('en-AU') : 'Awaiting activation'}</small>")

p='components/BrokerWorkspace.tsx'
replace(p,'{kind===\'clients\'?<Link className="button" href="/dashboard#invite">Invite client</Link>:<button', '{kind===\'clients\'?<><Link className="button" href="/dashboard#invite">Invite client</Link><Link className="button secondary" href="/clients/import">Import existing clients (CSV)</Link></>:<button')

p='app/theme-consistency.css'
replace(p,'/* Keep the dashboard banner legible after the common heading colour is applied. */', """/* BrokerDesk client navigation: themed, accessible and mobile-friendly. */
.brokerDeskClientActions{display:flex;gap:10px;flex-wrap:wrap;margin-top:12px}
.brokerDeskClientActions .brokerDeskClientAction{
  display:inline-flex;align-items:center;justify-content:center;
  padding:9px 13px;border:1px solid currentColor;border-radius:9px;
  color:var(--broker-company-link,#1d4ed8);background:#fff;
  font-size:13px;font-weight:700;line-height:1.3;text-decoration:none;
  transition:background-color .15s ease,box-shadow .15s ease;
}
.brokerDeskClientActions .brokerDeskClientAction:hover{background:#f2f6ff;text-decoration:underline}
.brokerDeskClientActions .brokerDeskClientAction:focus-visible{outline:3px solid #93b4fc;outline-offset:2px}
@media(max-width:620px){.brokerDeskClientActions{width:100%}.brokerDeskClientActions .brokerDeskClientAction{flex:1 1 180px;text-align:center}}

/* Keep the dashboard banner legible after the common heading colour is applied. */""")

for file, updated in changes.items():
    before = file.read_text(encoding='utf-8')
    print(''.join(unified_diff(before.splitlines(True), updated.splitlines(True), fromfile=str(file.relative_to(root)), tofile=str(file.relative_to(root)))))
for file, updated in changes.items():
    file.write_text(updated, encoding='utf-8')
print(f'Updated {len(changes)} files. Run npm ci && npm run build, and review git diff before commit.')
