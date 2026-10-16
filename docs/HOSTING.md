# Hosting report: Brazilian backend, gateways in Brazil and Europe

First version 2026-10-12. Rewritten 2026-10-16 after the reliability check.
Prices are from the providers' own pages or price APIs unless marked "third-party" or "not confirmed".
Exchange rates: 1 USD = R$ 5.0521 and 1 EUR = R$ 5.6609 (BCB PTAX sell rates of 2026-10-15). So 1 EUR = 1.1205 USD.
Cloud prices per hour are turned into months with 730 hours. Oracle bills 744 hours, so its months use 744.
I did not sign up or contact anyone. Marketing numbers (Tbps, "game filters") are the providers' claims. None were tested.
Payment method is listed for reference only. The owner said Pix and BRL billing do not matter (2026-10-16).

## 0. Key points first

- The owner wants only hosts with a reliable record. The 2026-10-16 check kept two of the earlier hosts: Hypehost and OVHcloud. Section 1 has the check, section 7 the rejected hosts.
- That check removed the old backend pick. So this report adds new backend candidates in São Paulo (section 2).
- The backend IP is never public. So the backend needs CPU, fast disk and a stable network. It does not need the best DDoS filter.
- The gateways take the attacks. They need strong game TCP filtering. They need little CPU or RAM.
- A gateway cannot lower latency. São Paulo to Europe is 171-189 ms either way. The EU gateway is for DDoS absorption near EU attackers. It is not a ping fix.
- BR players must never pass through the EU gateway. That would cost about 360 ms round trip.
- OVHcloud has no Brazilian region. Its nearest region is about 100-130 ms from São Paulo. So OVH is for EU gateways only.
- The login server hands the client one game host name (`ip` in config.lua, see LAUNCH.md). Use GeoDNS on that one name (section 5).
- Every cloud candidate uses network disks, not local NVMe. Our slow COMMITs came from a shared disk. Run the disk check from LAUNCH.md on any cloud backend before launch.

## 1. Reliability check of 2026-10-16

Rule: a Trustpilot score of 4.0 or more from many reviews, or a major provider with a public SLA.

| Host | Trustpilot | Reclame Aqui | Result |
|---|---|---|---|
| Hypehost | 4.8 from 134 reviews, 21 in the last 12 months. Claimed since Mar 2021. Has not replied to negative reviews | No profile found. A third-party check site also found none. Domain owner: JSK Cloud e Infraestrutura LTDA | Kept |
| OVHcloud | 3.8 from 8,886 reviews. Replies to 85% of negative reviews, within a week | Not Brazilian | Kept as a major provider with a public SLA |

Sources:
- https://br.trustpilot.com/review/hypehost.com.br (checked 2026-10-16)
- https://www.siteconfiavel.com.br/site/hypehost-com-br (third-party, checked 2026-10-16)
- https://www.trustpilot.com/review/ovhcloud.com (checked 2026-10-16)

Reclame Aqui pages return 403 to my tools. The verdicts below come from search results only.

## 2. Backend candidates in São Paulo

Needs: SP datacenter for under 20 ms to Brazilian players. Fast single core, ideally 4+ GHz, because the TFS game loop is one thread. 6+ cores, 32+ GB RAM, NVMe. Dedicated better than shared vCPU. Basic DDoS protection. Monthly billing. About 400 players at launch.

On clouds a vCPU is one hardware thread, so 16 vCPU = 8 cores. Azure Fasv6 is the exception: one vCPU is one full core.

### 2a. Summary

| # | Provider and plan | CPU | Cores, RAM, disk | Price/month | Reputation | Verdict |
|---|---|---|---|---|---|---|
| 1 | Hypehost bare metal mini-ryzen | AMD Ryzen 5 5500, Zen 3, 3.6 GHz base, 4.2 GHz boost (third-party spec) | 6c/12t, 32 GB DDR4, 1x250 GB NVMe, 1 Gbps | R$ 850 (US$ 168) | Trustpilot 4.8 / 134 | Best value. Real dedicated box. Small disk. 10 business days to deliver |
| 2 | Oracle Cloud VM.Standard.E6.Flex, 8 OCPU, 32 GB | AMD EPYC 9J45, 2.7 GHz base, 4.1 GHz boost | 8 cores, 32 GB, block volume | US$ 226 + disk about US$ 12 (R$ 1,203) | Major provider. SLA page not reachable | Best cloud price. Confirm SP shape stock, SLA and DDoS first |
| 3 | Azure Standard_F8as_v6, Brazil South | AMD EPYC 9004 (Genoa), up to 3.7 GHz, no SMT | 8 full cores, 32 GiB, managed disk | US$ 640 + disk + egress (R$ 3,234+) | Major provider. Public SLA | Good fit, full cores. Costly |
| 4 | AWS c8i.4xlarge, sa-east-1 | Intel Xeon Granite Rapids, 3.9 GHz | 16 vCPU (8 cores), 32 GiB, EBS | US$ 843 + EBS + egress (R$ 4,261+) | Major provider. Public SLA | Most proven network. Most expensive. Egress is billed |
| 5 | Google Cloud c4-highcpu-16, southamerica-east1 | Intel Xeon Granite or Emerald Rapids, 3.9 GHz all-core, 4.2 GHz max | 16 vCPU (8 cores), 32 GB, Hyperdisk | About US$ 788 (third-party, not confirmed) | Major provider | Price not confirmed from Google. Not used in the setups |
| 6 | BattleHost Ryzen 9 7950X | AMD Ryzen 9 7950X, 4.5 GHz base, 5.7 GHz boost | 16c/32t, 128 GB DDR5, 2 TB NVMe, 10 Gbps | R$ 1,899 (US$ 376) | Trustpilot 4.3 / 169, but only 4 in the last 12 months | Fastest core here. Weak recent evidence. Conditional |

None of these are tested. The earlier load test ran on 2.1 GHz Xeon vCPUs. The game loop thread was 39-50% busy at 300 bots. RSS was 4.65 GB. Any of these cores should give clear headroom for 400. That is an estimate, not a measurement.

### 2b. Details

**1. Hypehost bare metal, mini-ryzen.** Checked 2026-10-16 at https://hypehost.com.br/baremetal
- R$ 850/month. In stock. Delivery "10 dias úteis". No setup fee.
- 1 Gbps, 5 IPs, unlimited traffic under the AUP.
- Cycles: monthly, quarterly -10%, semiannual -15%, annual -30%.
- Payment: cards, Pix, PayPal, boleto, transfer, Mercado Pago.
- DDoS: "AntiDDoS PRO" included. Site-wide claim: 12+ Tb/s, 8+ scrubbing PoPs, Tibia filters. No numbers for bare metal.
- Datacenter: Osasco, SP, Tier III, on IX.br (homepage claim).
- SLA: 99.7% with service credits, all plans (homepage, https://hypehost.com.br/). No separate bare metal terms.
- Other SP bare metal on the page is out of stock: Ryzen 9 7900X R$ 2,100, Ryzen 9 5900XT R$ 2,200, Ryzen 9 9900X R$ 3,600.
- CPU clocks are from retailer listings. AMD's own page was not reached.
- Risks: 250 GB is small for DB plus backups. Keep backups off the box. Gateways and backend at one provider is a single point of failure. The Tibia filter may drop our PROXY v2 header from the gateways. Ask them to whitelist gateway IPs.

**2. Oracle Cloud (OCI), São Paulo.** Prices from Oracle's price list API, checked 2026-10-16: https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?currencyCode=USD
- E6 Standard: US$ 0.03 per OCPU-hour, US$ 0.002 per GB-hour. 1 OCPU = 2 vCPU = 1 core.
- 8 OCPU plus 32 GB = US$ 0.304/hour = US$ 226.18/month at 744 hours.
- 6 OCPU plus 32 GB would be US$ 181.54/month.
- Block volume: US$ 0.0255 per GB-month plus US$ 0.0017 per performance unit. 200 GB at 20 units (higher performance) = US$ 11.90/month.
- Outbound data: first 10 TB/month free from South America, then US$ 0.025/GB.
- CPU: EPYC 9J45, 2.7 GHz base, 4.1 GHz boost. Oracle lists these for the E6 series: https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm
- SP and Vinhedo availability of E6.Flex: third-party only, https://northflank.com/cloud/oci/instances/VM.Standard.E6.Flex. Not confirmed by Oracle.
- Not confirmed: the compute SLA and the free DDoS protection. Oracle's SLA and pricing pages returned 403.
- Billing: pay as you go, by card. Pix not confirmed.
- Risks: new tenancies often have low service limits. Request the limit increase early. Network block storage, so run the disk check.

**3. Azure, Brazil South.** Price from the Azure Retail Prices API, checked 2026-10-16: https://prices.azure.com/api/retail/prices
- Standard_F8as_v6, Linux, pay as you go: US$ 0.877/hour = US$ 640.21/month.
- Specs: https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/compute-optimized/fasv6-series. 8 vCPU, each a full physical core. 32 GiB. No local disk.
- Disk and egress are extra. Not priced here.
- DDoS: default infrastructure protection, L3/L4, free. Paid DDoS IP Protection is extra. https://learn.microsoft.com/en-us/azure/ddos-protection/ddos-protection-overview
- SLA: 99.9% for a single VM with Premium SSD or better disks. Source is a 2023 Microsoft Q&A answer. The current SLA page was not checked.
- Billing: card, monthly in arrears.

**4. AWS, sa-east-1.** Prices from the AWS price list file of 2026-10-15, checked 2026-10-16: https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/sa-east-1/index.csv
- c8i.4xlarge, Linux on demand: US$ 1.15544/hour = US$ 843.47/month. 16 vCPU, 32 GiB, Granite Rapids 3.9 GHz.
- c7i.4xlarge: US$ 1.1004/hour = US$ 803.29/month. 1-year reserved, no upfront: US$ 0.72677/hour = US$ 530.54/month. Sapphire Rapids 3.2 GHz.
- c7a is not offered in sa-east-1. The file has no c7a rows.
- EBS gp3: US$ 0.152 per GB-month. 200 GB = US$ 30.40.
- Egress to the internet: first 100 GB free, then US$ 0.15/GB up to 10 TB. Source: https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSDataTransfer/current/sa-east-1/index.csv. All game traffic to the gateways counts. Each TB costs about US$ 150.
- DDoS: Shield Standard, L3/L4, free. https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html
- SLA: 99.5% per instance, 99.99% across zones. https://aws.amazon.com/compute/sla/
- Billing: card, monthly in arrears, USD.

**5. Google Cloud, southamerica-east1.**
- C4, C3, N4, N2 and others are offered in all three SP zones. C4D is not. https://docs.cloud.google.com/compute/docs/regions-zones
- C4 clocks: 3.9 GHz all-core turbo, 4.2 GHz max. https://docs.cloud.google.com/compute/docs/general-purpose-machines
- Price not confirmed. Google's pricing page did not load. Third-party: c4-highcpu-16 at US$ 1.080/hour, about US$ 788/month. https://www.devzero.io/instances/gcp/c4-highcpu-16 (no date on the page)
- SLA not confirmed. The SLA page did not load.

**6. BattleHost, Ryzen 9 7950X.** Checked 2026-10-16 at https://battlehost.com.br/dedicado
- R$ 1,899/month. Listed as orderable. Activation 24 hours. SP.
- Also Ryzen 9 9950X, 128 GB, 2 TB NVMe, R$ 2,199, 72 hours. Smaller Ryzen plans are sold out.
- DDoS: "100Tbps de capacidade", no details. SLA and payment methods not stated.
- CNPJ 29.769.848/0001-61.
- Trustpilot 4.3 from 169 reviews, only 4 in the last 12 months. Replies to 66% of negatives. https://br.trustpilot.com/review/battlehost.com.br
- Reclame Aqui (search result only): no score yet, fewer than 10 rated complaints in the Jan-Jun 2026 period. 35 complaints in total. A June 2026 complaint: server not activated after 17 hours, then a full refund.

**Also checked, not ranked.** Akamai/Linode Dedicated 32 GB in SP: 16 dedicated vCPU, 640 GB, US$ 403.20/month. CPU model and clock are not stated per plan. Source: https://api.linode.com/v4/linode/types (checked 2026-10-16).

## 3. Gateway options

Our HAProxy on each gateway adds the PROXY v2 header and the per-IP limits. So a gateway only needs a VPS that forwards raw TCP. The host does not need to support PROXY v2 itself.

### 3a. BR gateway: Hypehost

| Plan | Specs | Price/month | DDoS | Notes |
|---|---|---|---|---|
| Plate Armor | 2 vCPU Ryzen, 4 GB, 60 GB NVMe | R$ 99 (US$ 19.60) | 12+ Tb/s claimed, 8+ PoPs, filters for Tibia packet and login floods | Monthly. 7-day refund. Root access |
| Silver Dagger | 3 vCPU, 6 GB, 80 GB NVMe | R$ 159 | same | Only if one gateway needs more CPU |

Source: https://hypehost.com.br/tibia (checked 2026-10-16). The page says nothing on PROXY protocol, custom ports or custom clients. SLA 99.7% per the homepage.

### 3b. EU gateway: OVHcloud

| Plan | Specs | Price/month | DDoS | Notes |
|---|---|---|---|---|
| VPS-1 | 2 vCores, 4 GB, 40 GB NVMe, 500 Mbit/s, unlimited traffic | EUR 3.81 excl. VAT (US$ 4.27, R$ 21.57). US page: US$ 4.54 | Anti-DDoS included, automatic. The Game firewall is only for Bare Metal Game servers | Price uses a 12-month upfront term. Monthly price without commitment not shown. SLA 99.9% (US page) |

Sources: https://www.ovhcloud.com/en-ie/vps/ and https://www.ovhcloud.com/en/vps/ (checked 2026-10-16). Game firewall: https://docs.ovhcloud.com/en/guides/bare-metal-cloud/dedicated-servers/firewall-game-ddos

The VPS page shows a map but no city list. Gravelines, Strasbourg, Frankfurt area, Warsaw and the UK were named in the FY25 report. Exact VPS cities are not confirmed: https://www.ovhcloud.com/sites/default/files/external_files/kpis_fy25.pdf

### 3c. OVH as backend: no

- OVH lists no region or Local Zone in Brazil. https://www.ovhcloud.com/en/public-cloud/regions-availability/ (checked 2026-10-16)
- A 2025 news piece said OVH planned Local Zones in Brazil. No opening was found. https://www.datacenterdynamics.com/es/noticias/ovhcloud-planea-nuevas-local-zones-en-m%C3%A9xico-chile-argentina-y-brasil-para-2025/
- Nearest OVH regions: Washington DC (VIN), Montreal (BHS), Toronto.
- Measured RTT, São Paulo to Ashburn: 101.7-128.0 ms. To New York: 107.7-122.0 ms. hatsnet.io round of 2026-10-15: https://hatsnet.io/docs/network/latency/gru-sao-paulo
- That is 5-6 times the 20 ms target. An OVH backend is not an option for BR players.

### 3d. Managed protection (fallback only)

Not part of the reliability check. Use only if self-run gateways keep falling.
- X4B: anycast TCP forwarding, PoPs in São Paulo, Amsterdam and London, from US$ 10/month. PROXY support not confirmed. https://www.x4b.net/
- Cloudflare Spectrum: TCP proxy with a PROXY header. Arbitrary ports need Enterprise. https://developers.cloudflare.com/spectrum/reference/configuration-options/

Warning on "Tibia filters". Our client is protocol 10.98 with our own client guard. A strict "Tibia only" filter may drop it. Test a real login through each gateway before paying for months.

Warning on the backend. The gateway sends a PROXY v2 header before the game bytes. A game-aware filter on the backend's network may drop that. This matters most for a Hypehost backend. Ask the host to whitelist the gateway IPs or turn the game filter off for them. The cloud filters are generic L3/L4 and should not care.

Never leak the backend IP. No DNS record, no website link, no mail header, no error page may show it. Firewall the game ports so only the gateway IPs can reach them. If the IP leaks, move the backend to a new IP.

## 4. Latency

Measured, hatsnet.io:

| Path | RTT |
|---|---|
| London to São Paulo | 171-176 ms |
| Paris to São Paulo | 175-180 ms |
| Amsterdam to São Paulo | 176-183 ms |
| Frankfurt to São Paulo | 181-189 ms |
| São Paulo to Miami | 74 ms |
| São Paulo and Ashburn | 102-128 ms |

Sources: https://hatsnet.io/docs/network/latency/regions/europe-to-south-america (2026-10-12) and https://hatsnet.io/docs/network/latency/gru-sao-paulo (2026-10-15)

Expected player ping:
- BR player via SP gateway: 10-30 ms inside Brazil (Hypehost's claim, not measured). The SP gateway to SP backend hop adds about 1-2 ms (estimate, same metro).
- Oracle also has Vinhedo, about 70 km from São Paulo. Expect a few ms more than SP. Not measured.
- EU player via EU gateway: about 10-30 ms to the gateway (estimate) plus 171-189 ms. So about 185-220 ms.
- BR player via EU gateway: about 350-380 ms. Never do this.
- Other Latin America: 50-80 ms per Hypehost's claim. Prefer the SP gateway for them.

## 5. Routing BR and EU players to the right gateway

Our login server returns one game host (`ip` in config.lua). The client connects to what it returns. Options:

1. **GeoDNS on the one name (recommended, no code change).** `play.example.org` answers BR/LatAm resolvers with the BR gateways and EU resolvers with the EU gateway. Keep TTL 300 or less. Some players use far-away resolvers and land on the wrong side. Give them a way out (option 3).
2. **Two server list entries.** This needs a change first. Either the login server returns the host the client logged in through, or each entry has its own login port and `ip`. Without that, both entries send players to the same game host.
3. **Client region option.** The client lets the player pick "Brazil" or "Europe" and uses `br.play...` or `eu.play...` for both login and game. Needs a client change so the game connection uses the chosen host.

## 6. Suggested setups

All totals use the rates at the top. OVH is excl. VAT. Cloud egress beyond the free tier is not included.

### Budget: R$ 1,069.57/month (US$ 211.71)

- Backend: Hypehost mini-ryzen, Ryzen 5 5500, 32 GB, 250 GB NVMe. R$ 850.
- BR gateways: 2x Hypehost Plate Armor. R$ 198.
- EU gateway: 1x OVH VPS-1. EUR 3.81 (R$ 21.57), 12-month term.
- Caveat: everything in Brazil sits with one provider. One Hypehost outage takes the game down. Hypehost does not reply to negative reviews. Ask about the PROXY v2 whitelist before ordering.

### Recommended (launch, 400 players): about R$ 1,444/month (US$ 286)

- Backend: Oracle Cloud E6.Flex in São Paulo, 8 OCPU, 32 GB, 200 GB higher-performance block volume. US$ 238.08 (R$ 1,202.81). 10 TB/month egress free.
- BR gateways: 2x Hypehost Plate Armor. R$ 198.
- EU gateways: 2x OVH VPS-1 at two different sites. EUR 7.62 (R$ 43.14).
- Why: backend and gateways sit at different providers. The backend has a big provider's network. The 4.1 GHz boost core is faster than the 5500.
- Before paying: confirm E6.Flex stock in SP for your tenancy, the compute SLA and the DDoS terms. Run the disk check.
- If Oracle fails these checks, use Hypehost mini-ryzen as the backend. That is the Budget setup with a second EU gateway.

### Premium: about R$ 4,799/month (US$ 950) plus AWS egress

- Backend: AWS c8i.4xlarge in sa-east-1 with 200 GB gp3. US$ 873.87 (R$ 4,414.88). Egress about US$ 150 per TB after the first 100 GB.
- Cheaper Premium variant: Azure F8as_v6 at US$ 640.21 plus disk and egress. 8 full cores.
- BR gateways: 2x Hypehost Plate Armor (R$ 198) plus a standby Oracle E6.Flex 1 OCPU, 4 GB in SP (US$ 28.27, R$ 142.82). A second provider for the BR side.
- EU gateways: 2x OVH VPS-1. R$ 43.14.
- Optional: an X4B account ready as a fallback front. Not reliability-checked.
- A hot standby backend is not priced here.

Before paying for any month:
- Ask each gateway host in writing: mitigation capacity, whether arbitrary TCP on 7171/7172/8090 is filtered or passed, whether they null-route, and who the upstream is.
- Test a full login through each gateway with our client. Check the PROXY header reaches the backend.
- Run the load test's disk check on the backend (the slow COMMIT warning in LAUNCH.md).
- Prefer monthly billing until each host is proven.

## 7. Rejected hosts

| Host | Reason | Date |
|---|---|---|
| Latitude.sh | Trustpilot 2.6 from 6 reviews. Recent account bans after KYC and a forced IP change | 2026-10-16 |
| Nice Hosting | 11 unverified 5-star reviews | 2026-10-16 |
| KernelHost | Too little review data | 2026-10-16 |
| Hostini | Too little review data. Brand does not match | 2026-10-16 |
| Havichost | Unpaid refunds | 2026-10-16 |
| OTH Host | Not on Trustpilot. Wrong stack | 2026-10-16 |
| Vultr | Trustpilot 1.5 from 586. Main theme: suspensions and terminations without warning. https://www.trustpilot.com/review/vultr.com | 2026-10-16 |
| Gcore | Trustpilot 2.3 from 48. Slow support, billing complaints. https://www.trustpilot.com/review/gcore.com | 2026-10-16 |
| StreetHosting | Trustpilot 4.7 but only 49 reviews. Profile claimed Mar 2025. Too little history. https://br.trustpilot.com/review/streethosting.com.br | 2026-10-16 |
| Hostinger VPS | Trustpilot 4.6 from 73,197 (replies to 99% of negative reviews). Brazil is a VPS location (support page updated 2026-09-15; city not named). Not a backend: shared AMD EPYC vCPU, clock not stated, our game loop needs a fast dedicated core. Not a gateway: Wanguard filtering only, no game-aware TCP filter. KVM 8 (8 vCPU, 32 GB, 400 GB NVMe) is US$ 25.99/month prepaid, renews at US$ 49.99. Fine for a staging or test server | 2026-10-16 |
| OVHcloud as backend | No Brazilian region. 102-128 ms from SP to Ashburn | 2026-10-16 |

Datalix and BuyVM from the first version were not reliability-checked. They are left out.

## 8. LGPD and privacy

- EU gateways see the IP of every player who uses them. This is a transfer of personal data to the EU. LGPD art. 33 allows it with proper safeguards.
- The privacy policy must say it: game connections may pass through servers in Brazil and in the EU (name the countries). The data is the IP address and connection times. Name the purpose: DDoS protection and routing. Keep log retention short and stated.
- A US cloud backend in São Paulo keeps the data in Brazil. Name the provider in the policy anyway.
- EU players are also covered by GDPR. The gateway host acts as a processor. Sign or accept each host's data processing terms.
- This is not legal advice. Have the policy text checked.
