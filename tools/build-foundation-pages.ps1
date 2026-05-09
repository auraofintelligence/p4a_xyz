$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$contentDir = Join-Path $root "content/foundation"
$pagesDir = Join-Path $root "pages"
$cacheVersion = "20260509-twinkle-video"

function Escape-Html {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return "" }
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Value
  )

  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Read-FoundationPages {
  Get-ChildItem -Path $contentDir -Filter "*.md" | Sort-Object Name | ForEach-Object {
    $raw = Get-Content -Path $_.FullName -Raw
    $match = [regex]::Match($raw, '(?s)```json foundation-page\s*(\{.*?\})\s*```')
    if (-not $match.Success) {
      throw "Missing json foundation-page block in $($_.FullName)"
    }

    $page = $match.Groups[1].Value | ConvertFrom-Json
    $page | Add-Member -NotePropertyName "sourceFile" -NotePropertyValue ("content/foundation/" + $_.Name) -Force
    $page
  }
}

function Get-Nav {
  param([string]$Active)

  $currentArchitecture = if ($Active -eq "architecture") { ' aria-current="page"' } else { "" }
  $currentLaw = if ($Active -eq "legal-rag") { ' aria-current="page"' } else { "" }

@"
<nav class="site-nav" data-nav aria-label="Main navigation">
  <a href="../index.html">Home</a>
  <a href="architecture.html"$currentArchitecture>Architecture</a>
  <a href="twinkle.html">Twinkle</a>
  <a href="rabbit-hole.html">Rabbit</a>
  <a href="deployment-gear.html">Gear</a>
  <a href="musicverse.html">Music</a>
  <a href="states.html">States</a>
  <a href="state-history.html">History</a>
  <a href="constitution.html">Constitution</a>
  <a href="legal-rag.html"$currentLaw>Law</a>
  <a href="civic-ledger.html">Ledger</a>
</nav>
"@
}

function Get-Header {
  param([string]$Active)

  $nav = Get-Nav -Active $Active
@"
<a class="skip-link" href="#main">Skip to content</a>
<header class="site-header">
  <a class="brand" href="../index.html"><span class="brand-mark">P4A</span><span class="brand-text"><strong>Purple Party</strong><span>for Australia</span></span></a>
  <button class="icon-button nav-toggle" type="button" data-nav-toggle aria-expanded="false" aria-label="Open navigation">Menu</button>
  $nav
</header>
"@
}

function Get-Footer {
@"
<footer class="site-footer"><div><p>P4A is currently a proposed movement and drafting project. Content is exploratory unless explicitly marked as adopted policy.</p><p>p4a.xyz - Less splash, more class.</p></div><nav class="footer-links" aria-label="Footer links"><a href="site-map.html">Site map</a></nav></footer>
"@
}

function Render-ResearchBadge {
  param([object]$Page)

  $run = Escape-Html $Page.researchRun
  $timezone = Escape-Html $Page.researchTimezone
  $status = Escape-Html $Page.researchStatus

@"
<div class="research-badge foundation-research" aria-label="Last research run">
  <span>Last research run</span>
  <strong>$run</strong>
  <small>$timezone - $status</small>
</div>
"@
}

function Render-Cards {
  param([object[]]$Cards)

  $Cards = @($Cards | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.title) })
  if ($null -eq $Cards -or $Cards.Count -eq 0) { return "" }

  $items = foreach ($card in $Cards) {
    $label = Escape-Html $card.label
    $title = Escape-Html $card.title
    $body = Escape-Html $card.body
@"
<article class="track-card">
  <span>$label</span>
  <strong>$title</strong>
  <p>$body</p>
</article>
"@
  }

  "<div class=""constitution-grid foundation-card-grid"">" + ($items -join "`n") + "</div>"
}

function Render-Tags {
  param([object[]]$Tags)

  $Tags = @($Tags | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($null -eq $Tags -or $Tags.Count -eq 0) { return "" }

  $items = foreach ($tag in $Tags) {
    "<code>$(Escape-Html $tag)</code>"
  }

  "<div class=""tag-strip"">" + ($items -join "") + "</div>"
}

function Render-Links {
  param([object[]]$Links)

  $Links = @($Links | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.href) })
  if ($null -eq $Links -or $Links.Count -eq 0) { return "" }

  $items = foreach ($link in $Links) {
    $label = Escape-Html $link.label
    $href = Escape-Html $link.href
    "<a href=""$href"">$label</a>"
  }

  "<div class=""source-links foundation-links"">" + ($items -join "") + "</div>"
}

function Render-Section {
  param([object]$Section)

  $id = Escape-Html $Section.id
  $eyebrow = Escape-Html $Section.eyebrow
  $heading = Escape-Html $Section.heading
  $paragraphs = foreach ($paragraph in @($Section.paragraphs)) {
    "<p>$(Escape-Html $paragraph)</p>"
  }
  $cards = Render-Cards -Cards @($Section.cards)
  $tags = Render-Tags -Tags @($Section.tags)
  $links = Render-Links -Links @($Section.links)

@"
<div class="feature-panel foundation-panel" id="$id">
  <p class="eyebrow">$eyebrow</p>
  <h2>$heading</h2>
  $($paragraphs -join "`n")
  $cards
  $tags
  $links
</div>
"@
}

function Render-NextLinks {
  param([object[]]$Links)

  if ($null -eq $Links -or $Links.Count -eq 0) { return "" }

  $items = foreach ($link in $Links) {
    $label = Escape-Html $link.label
    $href = Escape-Html $link.href
    $style = if ($link.style -eq "primary") { "button button-primary" } else { "button button-secondary" }
    "<a class=""$style"" href=""$href"">$label</a>"
  }

  "<div class=""next-trail"">" + ($items -join "") + "</div>"
}

function Render-FoundationPage {
  param([object]$Page)

  $title = Escape-Html $Page.title
  $description = Escape-Html $Page.metaDescription
  $slug = Escape-Html $Page.slug
  $header = Get-Header -Active $Page.slug
  $footer = Get-Footer
  $heroImage = Escape-Html $Page.heroImage
  $heroAlt = Escape-Html $Page.heroImageAlt
  $eyebrow = Escape-Html $Page.eyebrow
  $heading = Escape-Html $Page.heading
  $heroCopy = Escape-Html $Page.heroCopy
  $primaryLabel = Escape-Html $Page.primaryCta.label
  $primaryHref = Escape-Html $Page.primaryCta.href
  $secondaryLabel = Escape-Html $Page.secondaryCta.label
  $secondaryHref = Escape-Html $Page.secondaryCta.href
  $researchBadge = Render-ResearchBadge -Page $Page
  $sections = foreach ($section in @($Page.sections)) {
    Render-Section -Section $section
  }
  $nextLinks = Render-NextLinks -Links @($Page.nextLinks)
  $sourceFile = Escape-Html $Page.sourceFile

@"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <meta name="description" content="$description">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../assets/favicon.svg">
  <link rel="stylesheet" href="../styles.css?v=$cacheVersion">
</head>
<body data-theme="royal" data-foundation-page="$slug">
  $header
  <div class="site-layer-strip national-layer" aria-label="Current site layer">
    <strong>National foundation workbench</strong>
    <span>This is a drafting workbench for roots-up civic tools. The scale model is flexible: private life, local communities, councils, bioregions, states, nations and future layers are design questions, not fixed doctrine.</span>
    <a href="architecture.html">Architecture</a>
    <a href="deployment-gear.html">Gear</a>
    <a href="legal-rag.html">Law Engine</a>
  </div>
  <main id="main">
    <section class="hero page-hero foundation-hero">
      <div class="hero-image"><img loading="eager" fetchpriority="high" decoding="async" src="$heroImage" alt="$heroAlt"></div>
      <div class="hero-content reveal">
        <p class="eyebrow">$eyebrow</p>
        <h1>$heading</h1>
        <p class="hero-copy">$heroCopy</p>
        <div class="hero-actions">
          <a class="button button-primary" href="$primaryHref">$primaryLabel</a>
          <a class="button button-secondary" href="$secondaryHref">$secondaryLabel</a>
        </div>
        $researchBadge
      </div>
    </section>
    <section class="section foundation-section" aria-label="Foundation content">
      <div class="page-shell foundation-shell">
        <aside class="page-media page-media-full reveal">
          <img loading="lazy" decoding="async" src="$heroImage" alt="$heroAlt">
          <div class="foundation-source-note">
            <span>Markdown source</span>
            <code>$sourceFile</code>
          </div>
        </aside>
        <div class="page-copy reveal">
          $($sections -join "`n")
          $nextLinks
        </div>
      </div>
    </section>
  </main>
  $footer
  <script src="../script.js?v=$cacheVersion"></script>
</body>
</html>
"@
}

$pages = Read-FoundationPages
foreach ($page in $pages) {
  $html = Render-FoundationPage -Page $page
  Write-Utf8NoBom -Path (Join-Path $pagesDir ($page.slug + ".html")) -Value $html
}

Write-Host "Generated $($pages.Count) foundation pages."
