# Hosting report: Brazilian backend, gateways in Brazil and Europe

Checked on 2026-10-12. Prices are from the providers' own pages unless marked otherwise.
Exchange rate used: 1 USD = R$ 5.21 (BCB PTAX of 2026-09-28, the latest found). 1 EUR is taken as about 1.08 USD.
I did not sign up or contact anyone. Marketing numbers (Tbps, "game filters") are the providers' claims. None were tested.

## 0. Key points first

- The design changes what each machine needs. The backend IP is never public. So the backend needs CPU, NVMe and a stable network. It does not need the best DDoS filter.
- The gateways take the attacks. They need the strong game TCP filtering. They need little CPU or RAM.
- A gateway cannot lower latency. São Paulo to Europe is 171-189 ms either way. The EU gateway is for DDoS absorption near EU attackers, and for routing. It is not a ping fix.
- BR players must never pass through the EU gateway. That would cost about 360 ms round trip.
- The login server hands the client one game host name (`ip` in config.lua, see LAUNCH.md). So "two server list entries" does not work alone. The login reply would send both groups to the same host. Use GeoDNS on the one name. Or change the client or engine first (see section 4).
- Small Brazilian "OT hosts" have the game-aware filters. They are young companies. Their reputation could not be verified. Big providers have strong networks but only generic L3/L4 filtering.

## 1. Brazilian providers (backend and BR gateways)

### 1a. Backend candidates (dedicated, fast cores, NVMe)

| Provider | Plan | Specs | Price/month | DDoS | Pix / BRL | Notes |
|---|---|---|---|---|---|---|
| Latitude.sh (SP, SAO and SAO2) | m4.metal.small | AMD 4244P, 6 cores at 3.8 GHz, 48 GB, 2x960 GB NVMe, 2x10 Gbps, 20 TB out | US$ 296 (about R$ 1,540) | In-house, 7 Tbps, L3/L4 and some L7, free. Null route about 2 h if an attack exceeds capacity | Not confirmed. A third-party listing says USD invoices, cards and PayPal | Real bare metal. Hourly or monthly, no long contract. Founded in Brazil (formerly Maxihost) |
| Latitude.sh | f4.metal.small | AMD 4484PX, 12 cores at 4.4 GHz, 96 GB, 2x960 GB NVMe | US$ 398 (about R$ 2,070) | same | same | Best single-core speed in this list |
| Latitude.sh | c3.small.x86 | Intel E-2386G, 6 cores at 3.5 GHz, 32 GB, 800 GB NVMe | US$ 190 (about R$ 990) | same | same | Older gen. Location count "+1": SP availability not confirmed |
| OTH Host (SP) | Ryzen 5 5600X | 6c/12t, 3.7-4.8 GHz, 32 GB, 512 GB NVMe, 1 Gbps | R$ 800 | "Anti-DDoS included", no details | Not stated on the page | Delivery 72 h. Company Mega Web Host LTDA, CNPJ 52.156.661/0001-04 |
| OTH Host | Ryzen 9 9900X | 12c/24t, 4.4-5.6 GHz, 128 GB DDR5, 2 TB NVMe, 10 Gbps | R$ 1,899 | same | same | Very fast core. Price is high for the RAM we do not need |
| Havichost (SP) | Ryzen 7 5800X | 8c/16t, 3.8-4.7 GHz, 32 GB, 1 TB NVMe, 1 Gbps | R$ 1,000 | 500 Tbps claimed, Cloudflare Magic Transit, UDP/TCP flood rules "calibrated for games" | Pix logo shown, also boleto, cards, PayPal | No setup fee. 7-day refund. Stock "consultar" |
| Havichost | Ryzen 9 5900X | 12c/24t, 3.7-4.8 GHz, 128 GB, 2 TB NVMe | R$ 1,600 | same | same | CNPJ 49.263.897/0001-35 |
| Vultr (SP) | Bare metal / High Frequency | HF 4 vCPU 16 GB listed at US$ 96 (third-party, US prices) | SP price not confirmed | Add-on US$ 10, 10 Gbps, L3/L4. Old forum reports say weak | Card, PayPal | Shared vCPU on HF. Not a good fit for the game loop |
| Akamai/Linode (SP) | Dedicated CPU | From about US$ 36-50 for 4 GB (third-party) | SP price not confirmed | Basic only | Card | Dedicated vCPU, but clock not high. Not recommended |
| BedHosting (Cosmópolis, SP) | Dedicated | Out of stock, price on request | Not confirmed | 22 Tbps claimed | Not stated | Own data center claimed |

Sources:
- Latitude.sh pricing: https://www.latitude.sh/pricing (checked 2026-10-12)
- Latitude.sh locations: https://www.latitude.sh/locations
- Latitude.sh DDoS: https://www.latitude.sh/docs/networking/ddos-protection
- Latitude.sh billing (third-party): https://www.whtop.com/plans/latitude.sh/128829
- OTH Host dedicated: https://othhost.com.br/servidor-dedicado
- Havichost dedicated: https://havichostbrasil.com/dedicado and https://havichostbrasil.com/
- Vultr HF listing (third-party): https://www.whtop.com/amp/plans/vultr.com/137626
- Vultr DDoS: https://docs.vultr.com/support/platform/billing/how-much-does-ddos-protection-cost
- Linode prices (third-party): https://costbench.com/software/cloud-infrastructure/linode
- BedHosting: https://bedhosting.com.br/dedicados

Fit with our numbers. The load test ran on 2.1 GHz Xeon vCPUs. The game loop thread was 39-50% busy at 300 bots. Any 3.8 GHz+ Zen 3 or newer core gives large headroom for 400. RSS was 4.65 GB, so 32 GB is plenty. The 430-670 ms COMMITs came from a shared disk. All candidates above have local NVMe.

### 1b. BR gateway candidates (small VPS with game-aware filtering in SP)

| Provider | Smallest useful plan | Price/month | DDoS claims | Pix | Notes |
|---|---|---|---|---|---|
| OTH Host | Gamer-01: 2 vCPU Ryzen 9 3.7-4.9 GHz, 2 GB, 40 GB NVMe, 1 Gbps | R$ 54.99 | L3/L4 layers, "filters for common game attacks". No capacity given | Not stated | 20/30/40% off for 12/24/36 months |
| Hypehost | Plate Armor: 2 vCPU Ryzen, 4 GB, 60 GB NVMe | R$ 99 | 12 Tbps, 8+ scrubbing PoPs, Tibia filters for packet and login floods | Yes, instant | No lock-in. 7-day refund. Trustpilot 4.8 with 123 reviews (category listing) |
| Nice Hosting | Tibia Starter: 3 vCPU at 4.7 GHz, 3 GB DDR5, 40 GB NVMe | R$ 115 | 500 Tbps claimed, filters per game and port, no charge per attack | Not stated | 7-day refund |
| Hostini | VPS from R$ 129.90, Ryzen 9 4.8-5.7 GHz, reserved cores | R$ 129.90 | Default deny: only traffic that looks like Tibia passes. Filter chosen per port | Not stated | 30-day refund. VPS support in business hours per FAQ |
| Gcore (SP and SP-2) | Basic VM | Not confirmed. 2023 news said from EUR 3.2 | Basic protection, 5 Gbps threshold in a 2023 document | Card | Large global network. Same provider has Amsterdam and Frankfurt |

Sources:
- OTH Host VPS: https://othhost.com.br/vps-gamer/ and https://othhost.com.br/host-tibia/
- Hypehost: https://hypehost.com.br/tibia
- Nice Hosting: https://nicehosting.com.br/jogos/host-tibia
- Hostini: https://hostini.io/tibia/
- Gcore SP: https://gcore.com/news/gcore-basic-in-sao-paulo and https://gcore.com/pricing/cloud
- Trustpilot category: https://br.trustpilot.com/categories/internet_software

Warning on "Tibia filters". Our client is protocol 10.98 with our own client guard. A strict "Tibia only" filter may drop it. Test a real login through each host before paying for months. Hostini's default-deny filter is the most likely to need tuning.

Warning on the backend. The gateway sends a PROXY v2 header before the game bytes. A game-aware filter on the backend's host may drop that. On the backend, ask the host to whitelist the gateway IPs or turn the game filter off for them. Latitude.sh's generic filter should not care.

Reputation. I found no independent OT-community reviews for 2025-2026. Search results were only the hosts' own pages. The CNPJ numbers of OTH and Havichost suggest companies opened around 2023. Ask on TibiaKing and OTLand and check Reclame Aqui before paying.

## 2. European gateway options

### 2a. Cheap VPS with good filtering

| Provider | Plan | Price/month | Locations | DDoS | Notes |
|---|---|---|---|---|---|
| OVHcloud | VPS-1: 2 vCores, 4 GB, 40 GB NVMe, 500 Mbit/s, unlimited traffic | EUR 4.53 (with 12-month commitment; monthly price not shown) | Gravelines, Strasbourg, Limburg (Frankfurt area), Warsaw, UK site (Erith). Exact VPS regions not confirmed | VAC always on, included. The Game firewall is only for Bare Metal Game servers and is mostly UDP | Very common in the game-server world. KYC can be strict |
| KernelHost | VPS from EUR 9.99 excl. VAT | Frankfurt (maincubes, DE-CIX) | Always on L3-L7, custom TCP/UDP services on any port covered | Prepaid, no minimum term |
| Datalix | Ryzen KVM from EUR 2.45, Epyc KVM from EUR 4.95 | Frankfurt (Equinix FR5/FR7/FR8) | Own "SmartMitigate", AS58087. No capacity or TCP details | Prepaid. 99.2% SLA |
| BuyVM | Slice 1024: 1 core 3.5 GHz+, 1 GB | US$ 3.50 + US$ 3.00 per protected IP | Roost, Luxembourg | Path.net, 3.5 Tbps+, TCP SYNPROXY filter for any TCP app | Page shows "Out of stock". Wiki is from 2021 |

Sources:
- OVHcloud VPS: https://www.ovhcloud.com/de/vps/ and https://www.ovhcloud.com/en/vps/
- OVHcloud game firewall: https://docs.ovhcloud.com/en/guides/bare-metal-cloud/dedicated-servers/firewall-game-ddos
- OVHcloud sites (FY25 report): https://www.ovhcloud.com/sites/default/files/external_files/kpis_fy25.pdf
- KernelHost: https://www.kernelhost.com/en/blog/specialized-game-ddos-protection
- Datalix: https://datalix.eu/
- BuyVM: https://buyvm.net/kvm-dedicated-server-slices/ and https://wiki.buyvm.net/doku.php/ddos

No good Lisbon option was found. EllaLink links Fortaleza and São Paulo to Lisbon and Madrid. No measured ping for it was found.

### 2b. Managed proxy and tunnel services

| Service | What it is | PROXY protocol | Price | Fit |
|---|---|---|---|---|
| X4B | Anycast TCP/UDP forwarding and "Protected Tunnel". 100 Gbps / 100 Mpps minimum per city | Not confirmed | From US$ 10/month | PoPs in São Paulo, Amsterdam, London, Switzerland. No Frankfurt. Could replace self-run gateways on both sides |
| Gcore DDoS Protection | PRO plan, GRE tunnel to your server, 200+ Tbps | Not stated | Quote, per Mbps, 100 Mbps minimum | Good as an upgrade path. Too expensive for the beta |
| aurologic flowShield / flowProxy | Filtering plus a TCP proxy. Remote protection by GRE or cross-connect | Not stated | Sold through resellers, not confirmed | Frankfurt-based network. Behind KernelHost-type resellers |
| Path.net | Filtering by resellers, GRE remote protection | Not stated | Via resellers like BuyVM | No São Paulo PoP confirmed |
| Cloudflare Spectrum | TCP proxy, can send a PROXY header | Mentioned, versions not confirmed | Arbitrary TCP ports need Enterprise. Quote only | Premium only |
| NeoProtect | Game Shield reverse proxy | Docs only cover Minecraft | About EUR 10-15 (competitor's claim) | Not a fit for a custom TCP game |

Sources:
- X4B: https://www.x4b.net/ and https://lowendspirit.com/discussion/1485/x4b-brazil-launch-30-off-for-new-customers
- Gcore: https://gcore.com/ddos-protection/servers
- aurologic: https://docs.aurologic.com/ddos-protection/introduction
- Path.net resellers: https://wiki.buyvm.net/doku.php/ddos
- Cloudflare Spectrum: https://developers.cloudflare.com/spectrum/reference/configuration-options/
- NeoProtect: https://docs.neoprotect.net/gameshield/proxyprotocol and https://mineguard.pro/en/blog/mineguard-vs-neoprotect-comparison-2026

Our own HAProxy gateways already send PROXY v2 and do the per-IP limits. So a cheap VPS on a well-filtered network is enough. A managed proxy is only needed if gateways keep falling.

## 3. Latency

Measured, hatsnet.io, round of 2026-10-12:

| Path | RTT |
|---|---|
| London to São Paulo | 171-176 ms |
| Paris to São Paulo | 175-180 ms |
| Amsterdam to São Paulo | 176-183 ms |
| Frankfurt to São Paulo | 181-189 ms |
| São Paulo to Miami | 74 ms |

Sources: https://hatsnet.io/docs/network/latency/regions/europe-to-south-america and https://hatsnet.io/docs/network/latency/gru-sao-paulo

Expected player ping:
- BR player via SP gateway: 7-40 ms inside Brazil (Havichost's and Nice's claims, not measured). The SP gateway to SP backend hop adds about 1-2 ms (estimate, same city).
- EU player via EU gateway: about 10-30 ms to the gateway (estimate) plus 171-189 ms. So about 185-220 ms. A direct path would be about the same.
- BR player via EU gateway: about 350-380 ms. Never do this.
- Other Latin America: not measured. Prefer the SP gateway for them.
- London or Paris is the best EU gateway site by RTT. Frankfurt is about 10 ms worse. Pick by the provider's filter quality first.

## 4. Routing BR and EU players to the right gateway

Our login server returns one game host (`ip` in config.lua). The client connects to what it returns. Options:

1. **GeoDNS on the one name (recommended, no code change).** `play.example.org` answers BR/LatAm resolvers with the BR gateways and EU resolvers with the EU gateway. Keep TTL 300 or less. Our docs already need one A record per gateway. GeoDNS just splits them by region. Some players use far-away resolvers and land on the wrong side. Give them a way out (option 3).
2. **Two server list entries.** This needs a change first. Either the login server returns the host the client logged in through, or each entry has its own login port and `ip`. Without that, both entries send players to the same game host.
3. **Client region option.** The client lets the player pick "Brazil" or "Europe" and uses `br.play...` or `eu.play...` for both login and game. Needs a client change so the game connection uses the chosen host.

## 5. Suggested setups

### Budget (beta, 300 players): about R$ 990/month (about US$ 190)

- Backend: OTH Host Ryzen 5 5600X, 32 GB, 512 GB NVMe. R$ 800.
- BR gateways: 2x OTH Host Gamer-01 at R$ 54.99. R$ 110. Better: one OTH plus one Hypehost Plate Armor (R$ 99) for provider diversity, R$ 154.
- EU gateway: 1x OVH VPS-1. EUR 4.53 (about R$ 27), 12-month commitment.
- Caveat: backend and BR gateways at one young provider. One outage can take everything. OTH's DDoS details are unknown.

### Recommended (launch, 400 players): about US$ 355/month (about R$ 1,850)

- Backend: Latitude.sh m4.metal.small in São Paulo. US$ 296. Real bare metal, 3.8 GHz, 48 GB, 2x960 GB NVMe, 7 Tbps network. Monthly, no long contract. Confirm SP stock. Pays in USD by card, Pix not confirmed.
- If BRL and Pix are a must: Havichost Ryzen 7 5800X at R$ 1,000 instead.
- BR gateways: Hypehost Plate Armor (R$ 99) plus Nice Hosting Tibia Starter (R$ 115). Two providers, both with Tibia-aware filters. R$ 214.
- EU gateways: OVH VPS-1 (EUR 4.53) plus KernelHost Frankfurt (from EUR 9.99 excl. VAT). Two different networks.
- Caveat: Latitude.sh's IP is null-routed if an attack exceeds its capacity. With the IP hidden that risk is small. Never leak it.

### Premium: about US$ 500-550/month plus optional managed protection

- Backend: Latitude.sh f4.metal.small. US$ 398. 4.4 GHz, 12 cores, 96 GB. Or OTH Ryzen 9 9900X at R$ 1,899 if Pix is needed.
- BR gateways: 3 providers (Hypehost, Nice, Hostini or Havichost VPS). About R$ 330-350.
- EU gateways: OVH VPS-1 plus KernelHost. About EUR 15-20.
- Standby: an X4B account (from US$ 10, PoPs in São Paulo and Amsterdam/London) ready as a fallback front. Or a Gcore GRE quote. Confirm PROXY protocol support before relying on X4B.
- A second backend for a hot standby is not priced here.

## 6. Ranked recommendation

1. **Recommended setup.** Latitude.sh SP backend, Hypehost plus Nice as BR gateways, OVH plus KernelHost as EU gateways, GeoDNS.
2. **Budget setup** for the beta, then move the backend to Latitude.sh or Havichost for launch.
3. **Premium setup** only if attacks keep beating the gateways.

Before paying for any month:
- Ask each gateway host in writing: mitigation capacity, whether arbitrary TCP on 7171/7172/8090 is filtered or passed, whether they null-route, and who the upstream is.
- Test a full login through each gateway with our client. Check the PROXY header reaches the backend.
- Run the load test's disk check on the backend (the slow COMMIT warning in LAUNCH.md).
- Prefer monthly billing until each host is proven.

## 7. LGPD and privacy

- EU gateways see the IP of every player who uses them. This is a transfer of personal data to the EU. LGPD art. 33 allows it with proper safeguards.
- The privacy policy must say it: game connections may pass through servers in Brazil and in the EU (name the countries). The data is the IP address and connection times. Name the purpose: DDoS protection and routing. Keep log retention short and stated.
- EU players are also covered by GDPR. The gateway host acts as a processor. Sign or accept each host's data processing terms.
- This is not legal advice. Have the policy text checked.
