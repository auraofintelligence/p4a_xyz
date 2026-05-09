$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$contentDir = Join-Path $root "content\states"
$historyContentDir = Join-Path $root "content\history"
$pagesDir = Join-Path $root "pages"
$statesDir = Join-Path $root "states"
$assetsDir = Join-Path $root "assets"
$culture = [System.Globalization.CultureInfo]::GetCultureInfo("en-AU")
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Escape-Html {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return "" }
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Format-DateLabel {
  param([string]$IsoDate)
  try {
    return ([DateTimeOffset]::Parse($IsoDate)).ToString("d MMM yyyy", $culture)
  } catch {
    return $IsoDate
  }
}

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Value
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Get-SortedElectionItems {
  param([array]$Items)

  $now = [DateTimeOffset]::Now
  return @($Items) | Sort-Object `
    @{ Expression = {
      try {
        $target = [DateTimeOffset]::Parse([string]$_.Event.date)
        if ($target -ge $now) { 0 } else { 1 }
      } catch {
        2
      }
    } }, `
    @{ Expression = {
      try {
        $target = [DateTimeOffset]::Parse([string]$_.Event.date)
        $stamp = $target.ToUnixTimeMilliseconds()
        if ($target -ge $now) { $stamp } else { -1 * $stamp }
      } catch {
        [long]::MaxValue
      }
    } }, `
    @{ Expression = { [string]$_.State.name } }, `
    @{ Expression = { [string]$_.Event.label } }
}

function Get-StateData {
  $files = Get-ChildItem -Path $contentDir -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name
  foreach ($file in $files) {
    $raw = Get-Content -LiteralPath $file.FullName -Raw
    $match = [regex]::Match($raw, '(?s)```json\s+state-data\s*(.*?)```')
    if (-not $match.Success) {
      throw "No ```json state-data block found in $($file.FullName)"
    }

    $state = $match.Groups[1].Value | ConvertFrom-Json
    $state | Add-Member -NotePropertyName "sourceMarkdown" -NotePropertyValue ("content/states/" + $file.Name) -Force
    $state
  }
}

function Get-HistoryData {
  if (-not (Test-Path -LiteralPath $historyContentDir)) {
    return
  }

  $files = Get-ChildItem -Path $historyContentDir -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name
  foreach ($file in $files) {
    $raw = Get-Content -LiteralPath $file.FullName -Raw
    $match = [regex]::Match($raw, '(?s)```json\s+history-data\s*(.*?)```')
    if (-not $match.Success) {
      throw "No ```json history-data block found in $($file.FullName)"
    }

    $history = $match.Groups[1].Value | ConvertFrom-Json
    $history | Add-Member -NotePropertyName "sourceMarkdown" -NotePropertyValue ("content/history/" + $file.Name) -Force
    $history
  }
}

function Get-Nav {
  param(
    [string]$Prefix,
    [string]$Active,
    [string]$CurrentStateSlug = "",
    [string]$CurrentStateShort = "",
    [string]$CurrentStateType = "state"
  )

  $currentStates = if ($Active -eq "states") { ' aria-current="page"' } else { "" }
  $currentHistories = if ($Active -eq "histories") { ' aria-current="page"' } else { "" }
  $currentState = if ($Active -eq "state-local") { ' aria-current="page"' } else { "" }
  $currentStateHistory = if ($Active -eq "state-history") { ' aria-current="page"' } else { "" }
  $currentStateArchitecture = if ($Active -eq "state-architecture") { ' aria-current="page"' } else { "" }
  $currentStateConstitution = if ($Active -eq "state-constitution") { ' aria-current="page"' } else { "" }
  $currentHome = if ($Active -eq "home") { ' aria-current="page"' } else { "" }
  $onStateLayer = @("state-local", "state-history", "state-architecture", "state-constitution") -contains $Active
  $statePortalLabel = if ($onStateLayer) { "National map" } else { "States" }
  $stateSiteLink = ""
  $architectureHref = "${Prefix}pages/architecture.html"
  $architectureCurrent = ""
  $historyHref = "${Prefix}pages/state-history.html"
  $historyCurrent = $currentHistories
  $constitutionHref = "${Prefix}pages/constitution.html"
  $constitutionCurrent = ""

  if ($onStateLayer -and -not [string]::IsNullOrWhiteSpace($CurrentStateSlug)) {
    $safeSlug = Escape-Html $CurrentStateSlug
    $safeStateShort = Escape-Html $CurrentStateShort
    if ([string]::IsNullOrWhiteSpace($safeStateShort)) {
      $safeStateShort = "State"
    }
    $safeStateType = Escape-Html $CurrentStateType
    if ([string]::IsNullOrWhiteSpace($safeStateType)) {
      $safeStateType = "state"
    }
    $safeStateType = $safeStateType.ToLowerInvariant()
    $architectureHref = "${Prefix}states/${safeSlug}/architecture/index.html"
    $architectureCurrent = $currentStateArchitecture
    $historyHref = "${Prefix}states/${safeSlug}/history/index.html"
    $historyCurrent = $currentStateHistory
    $constitutionHref = "${Prefix}states/${safeSlug}/constitution/index.html"
    $constitutionCurrent = $currentStateConstitution
    $stateSiteLink = @"
  <a href="${Prefix}states/${safeSlug}/index.html"$currentState data-nav-layer="state-site" aria-label="$safeStateShort $safeStateType overview">$safeStateShort overview</a>
"@
  }

@"
<nav class="site-nav" data-nav aria-label="Main navigation">
  <a href="${Prefix}index.html"$currentHome>Home</a>
  <a href="$architectureHref"$architectureCurrent>Architecture</a>
  <a href="${Prefix}pages/twinkle.html">Twinkle</a>
  <a href="${Prefix}pages/rabbit-hole.html">Rabbit</a>
  <a href="${Prefix}pages/deployment-gear.html">Gear</a>
  <a href="${Prefix}pages/musicverse.html">Music</a>
  <a href="${Prefix}pages/states.html"$currentStates data-nav-layer="national-map">$statePortalLabel</a>
  <a href="$historyHref"$historyCurrent data-nav-layer="history-index">History</a>
  <a href="$constitutionHref"$constitutionCurrent>Constitution</a>
  <a href="${Prefix}pages/legal-rag.html">Law</a>
  <a href="${Prefix}pages/civic-ledger.html">Ledger</a>
$stateSiteLink
</nav>
"@
}

function Get-Header {
  param(
    [string]$Prefix,
    [string]$Active,
    [string]$CurrentStateSlug = "",
    [string]$CurrentStateShort = "",
    [string]$CurrentStateType = "state"
  )

  $nav = Get-Nav -Prefix $Prefix -Active $Active -CurrentStateSlug $CurrentStateSlug -CurrentStateShort $CurrentStateShort -CurrentStateType $CurrentStateType
@"
<a class="skip-link" href="#main">Skip to content</a>
<header class="site-header">
  <a class="brand" href="${Prefix}index.html"><span class="brand-mark">P4A</span><span class="brand-text"><strong>Purple Party</strong><span>for Australia</span></span></a>
  <button class="icon-button nav-toggle" type="button" data-nav-toggle aria-expanded="false" aria-label="Open navigation">Menu</button>
  $nav
</header>
"@
}

function Get-SiteLayerStrip {
  param(
    [string]$Prefix,
    [string]$Layer,
    [string]$StateName = "",
    [string]$StateShort = "",
    [string]$StateType = "",
    [string]$StateSlug = ""
  )

  if ($Layer -eq "state") {
    $safeName = Escape-Html $StateName
    $safeShort = Escape-Html $StateShort
    $safeType = Escape-Html $StateType
    if ([string]::IsNullOrWhiteSpace($safeType)) {
      $safeType = "state"
    }
    $safeType = $safeType.ToLowerInvariant()
    $safeSlug = Escape-Html $StateSlug
    $stateArchitectureLink = if (-not [string]::IsNullOrWhiteSpace($safeSlug)) { "<a href=""${Prefix}states/${safeSlug}/architecture/index.html"">Architecture builder</a>" } else { "" }
    $stateConstitutionLink = if (-not [string]::IsNullOrWhiteSpace($safeSlug)) { "<a href=""${Prefix}states/${safeSlug}/constitution/index.html"">Constitution builder</a>" } else { "" }
@"
<div class="site-layer-strip state-layer" aria-label="Current site layer">
  <strong>$safeShort $safeType site</strong>
  <span>You are inside the $safeName clone. The national map is one level up; council and local layers come next.</span>
  $stateArchitectureLink
  $stateConstitutionLink
  <a href="${Prefix}pages/states.html">National state map</a>
  <a href="${Prefix}index.html">National home</a>
</div>
"@
  } else {
@"
<div class="site-layer-strip national-layer" aria-label="Current site layer">
  <strong>National P4A site</strong>
  <span>You are on the national layer. Choose a state or territory clone before future council and local layers.</span>
  <a href="${Prefix}pages/states.html">Open state map</a>
</div>
"@
  }
}

function Get-Foot {
  param([string]$Prefix)
@"
<footer class="site-footer state-footer">
  <div>
    <strong>P4A state portal</strong>
    <span>Data-first pages generated from markdown files future agents can update.</span>
  </div>
  <nav aria-label="State portal footer links">
    <a href="${Prefix}index.html">National page</a>
    <a href="${Prefix}pages/states.html">State map</a>
    <a href="${Prefix}pages/state-history.html">State histories</a>
    <a href="${Prefix}pages/site-map.html">Site map</a>
    <a href="${Prefix}content/states/README.md">State data notes</a>
    <a href="${Prefix}content/history/README.md">History data notes</a>
  </nav>
</footer>
"@
}

function Get-StateHref {
  param(
    [string]$Prefix,
    [string]$Slug
  )
  return "${Prefix}states/${Slug}/index.html"
}

function Render-TimerControls {
  param([string]$Label)

  $safeLabel = Escape-Html $Label
@"
<div class="timer-controls" data-timer-controls aria-label="$safeLabel timer controls">
  <label class="timer-sort-label">
    <span>Sort timers</span>
    <select data-timer-sort>
      <option value="next">Soonest next</option>
      <option value="byelections">By-elections first</option>
      <option value="farthest">Farthest future</option>
      <option value="state">State A-Z</option>
      <option value="days-since">Days since / held</option>
    </select>
  </label>
  <div class="segmented-control" role="group" aria-label="Timer display">
    <button type="button" class="is-active" data-timer-mode="clock" aria-pressed="true">Clock</button>
    <button type="button" data-timer-mode="days" aria-pressed="false">Days until/since</button>
  </div>
  <div class="segmented-control" role="group" aria-label="Timer filter">
    <button type="button" class="is-active" data-timer-filter="all" aria-pressed="true">All</button>
    <button type="button" data-timer-filter="upcoming" aria-pressed="false">Upcoming</button>
    <button type="button" data-timer-filter="by-election" aria-pressed="false">By-elections</button>
    <button type="button" data-timer-filter="since" aria-pressed="false">Days since</button>
  </div>
</div>
"@
}

function Render-ElectionCard {
  param(
    [object]$State,
    [object]$Event,
    [string]$ExtraClass
  )

  $slug = Escape-Html $State.slug
  $name = Escape-Html $State.name
  $label = Escape-Html $Event.label
  $date = Escape-Html $Event.date
  $dateLabel = Escape-Html (Format-DateLabel $Event.date)
  $kind = Escape-Html $Event.kind
  $status = Escape-Html $Event.status
  $note = Escape-Html $Event.note
  $scope = Escape-Html $Event.scope
  $source = Escape-Html $Event.source
  $metrics = $Event.dayMetrics
  $showDaysUntil = if ($null -eq $metrics -or $metrics.displayDaysUntil -ne $false) { "true" } else { "false" }
  $showDaysSince = if ($null -eq $metrics -or $metrics.displayDaysSince -ne $false) { "true" } else { "false" }
  $archiveDaysSince = if ($null -ne $metrics -and $metrics.archiveDaysSince -eq $false) { "false" } else { "true" }
  $cycleKey = if ($null -ne $metrics) { Escape-Html $metrics.cycleKey } else { "" }
  $archiveWithCycle = if ($null -ne $metrics) { Escape-Html $metrics.archiveWithCycle } else { "" }
  $archiveNote = if ($null -ne $metrics) { Escape-Html $metrics.archiveNote } else { "Days-since archive rule still needs to be added to the markdown data." }
  $daysSinceDate = if ($null -ne $metrics -and -not [string]::IsNullOrWhiteSpace([string]$metrics.daysSinceDate)) { Escape-Html $metrics.daysSinceDate } else { "" }
  $daysSinceLabel = if ($null -ne $metrics -and -not [string]::IsNullOrWhiteSpace([string]$metrics.daysSinceLabel)) { Escape-Html $metrics.daysSinceLabel } else { "Days-since reference date not yet set in markdown." }
  $daysSinceSource = if ($null -ne $metrics -and -not [string]::IsNullOrWhiteSpace([string]$metrics.daysSinceSource)) { Escape-Html $metrics.daysSinceSource } else { "" }
  $daysSinceSourceLink = if ([string]::IsNullOrWhiteSpace($daysSinceSource)) { "" } else { "<a class=""timer-meta-link"" href=""$daysSinceSource"">Days-since source</a>" }
@"
<article class="election-timer $ExtraClass" data-election-card data-state="$slug" data-election-date="$date" data-days-since-date="$daysSinceDate" data-days-since-label="$daysSinceLabel" data-election-scope="$scope" data-election-kind="$kind" data-election-label="$label" data-days-until-enabled="$showDaysUntil" data-days-since-enabled="$showDaysSince" data-archive-days-since="$archiveDaysSince" data-cycle-key="$cycleKey" data-archive-with-cycle="$archiveWithCycle">
  <div class="timer-topline"><span>$name</span><span>$kind</span></div>
  <h3>$label</h3>
  <p class="countdown-value" data-countdown="$date">Checking timer...</p>
  <dl class="timer-day-metrics">
    <div data-days-until-wrap><dt>Days until</dt><dd data-days-until>Checking...</dd></div>
    <div data-days-since-wrap><dt>Days since</dt><dd data-days-since>Checking...</dd></div>
  </dl>
  <p class="timer-date">$dateLabel</p>
  <p class="timer-status">$status</p>
  <p>$note</p>
  <p class="timer-archive-note timer-since-note"><span>Days-since reference</span><small>$daysSinceLabel</small></p>
  $daysSinceSourceLink
  <p class="timer-archive-note"><span>Archive rule</span><small>$archiveNote</small></p>
  <a href="$source">Source</a>
</article>
"@
  }

function Render-ElectionCards {
  param(
    [object]$State,
    [string]$ExtraClass
  )

  $items = foreach ($event in @($State.elections)) {
    [pscustomobject]@{ State = $State; Event = $event }
  }

  $cards = foreach ($item in (Get-SortedElectionItems -Items $items)) {
    Render-ElectionCard -State $item.State -Event $item.Event -ExtraClass $ExtraClass
  }

  return ($cards -join "`n")
}

function Render-AllElectionCards {
  param(
    [array]$States,
    [string]$ExtraClass
  )

  $items = foreach ($state in $States) {
    foreach ($event in @($state.elections)) {
      [pscustomobject]@{ State = $state; Event = $event }
    }
  }

  $cards = foreach ($item in (Get-SortedElectionItems -Items $items)) {
    Render-ElectionCard -State $item.State -Event $item.Event -ExtraClass $ExtraClass
  }

  return ($cards -join "`n")
}

function Render-Composition {
  param([object]$Chamber)

  $rows = foreach ($party in @($Chamber.composition)) {
    $seats = [int]$party.seats
    $pct = 0
    if ([int]$Chamber.seats -gt 0) {
      $pct = [Math]::Round(($seats / [double]$Chamber.seats) * 100, 1)
    }
    $width = [Math]::Max(2, [Math]::Min(100, $pct))
    $widthCss = $width.ToString("0.##", $invariant)
    $partyName = Escape-Html $party.party
    $short = Escape-Html $party.short
    $memberList = ""
    if (($party.PSObject.Properties.Name -contains "members") -and $null -ne $party.members) {
      $memberItems = foreach ($member in @($party.members)) {
        $memberName = Escape-Html $member.name
        $memberSeat = Escape-Html $member.seat
        if ([string]::IsNullOrWhiteSpace($memberSeat)) {
          "<li><strong>$memberName</strong></li>"
        } else {
          "<li><strong>$memberName</strong><small>$memberSeat</small></li>"
        }
      }
      if (@($memberItems).Count -gt 0) {
        $memberList = @"
  <ul class="party-members" aria-label="Named members">
    $($memberItems -join "`n    ")
  </ul>
"@
      }
    }
    $memberSourceLink = ""
    if (($party.PSObject.Properties.Name -contains "memberSource") -and -not [string]::IsNullOrWhiteSpace([string]$party.memberSource)) {
      $memberSource = Escape-Html $party.memberSource
      $memberSourceLink = "<a class=""member-source"" href=""$memberSource"">Named member source</a>"
    }
@"
<li class="party-row">
  <div class="party-label"><strong>$partyName</strong><small>$short</small>$memberList$memberSourceLink</div>
  <span class="party-bar" aria-hidden="true"><span style="width: $widthCss%"></span></span>
  <span class="party-seats">$seats</span>
</li>
"@
  }

  return ($rows -join "`n")
}

function Render-Chambers {
  param([object]$State)

  $cards = foreach ($chamber in @($State.chambers)) {
    $name = Escape-Html $chamber.name
    $type = Escape-Html $chamber.type
    $seats = Escape-Html $chamber.seats
    $majority = Escape-Html $chamber.majority
    $note = Escape-Html $chamber.note
    $source = Escape-Html $chamber.source
    $rows = Render-Composition -Chamber $chamber
@"
<article class="chamber-card">
  <div class="chamber-card-head">
    <div>
      <p class="eyebrow">$type</p>
      <h3>$name</h3>
    </div>
    <div class="seat-total"><strong>$seats</strong><span>seats</span></div>
  </div>
  <p class="majority-line">Majority line: $majority seats</p>
  <ul class="party-list">
    $rows
  </ul>
  <p>$note</p>
  <a href="$source">Chamber source</a>
</article>
"@
  }

  return ($cards -join "`n")
}

function Render-Sources {
  param([object]$State)

  $items = foreach ($source in @($State.sources)) {
    $label = Escape-Html $source.label
    $url = Escape-Html $source.url
    "<li><a href=""$url"">$label</a></li>"
  }
  return ($items -join "`n")
}

function Render-StrategyNotes {
  param([object]$State)

  $items = foreach ($note in @($State.strategyNotes)) {
    "<li>$(Escape-Html $note)</li>"
  }
  return ($items -join "`n")
}

function Render-StateArchitecturePage {
  param(
    [object]$State,
    [string]$StateOutDir
  )

  $slug = [string]$State.slug
  $name = Escape-Html $State.name
  $short = Escape-Html $State.shortName
  $capital = Escape-Html $State.capital
  $stateType = Escape-Html $State.stateType
  $research = Escape-Html $State.researchRun
  $timezone = Escape-Html $State.researchTimezone
  $researchStatus = Escape-Html $State.researchStatus
  $sourceMarkdown = Escape-Html $State.sourceMarkdown
  $prefix = "../../../"
  $header = Get-Header -Prefix $prefix -Active "state-architecture" -CurrentStateSlug $slug -CurrentStateShort $short -CurrentStateType $stateType
  $layerStrip = Get-SiteLayerStrip -Prefix $prefix -Layer "state" -StateName $name -StateShort $short -StateType $stateType -StateSlug $slug
  $footer = Get-Foot -Prefix $prefix
  $outDir = Join-Path $StateOutDir "architecture"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  $html = @"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>P4A | $name architecture builder</title>
  <meta name="description" content="P4A $name architecture builder for local council drill-downs, state electorates, bioregions, First Nations protocol maps, public ledgers and state-level civic simulation.">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../../../assets/favicon.svg">
  <link rel="stylesheet" href="../../../styles.css?v=20260509-twinkle-video">
</head>
<body data-theme="royal" data-state-page="$slug-architecture">
  $header
  $layerStrip
  <main id="main" class="state-site-main builder-site-main">
    <section class="state-hero state-detail-hero">
      <div class="state-hero-bg"><img loading="eager" fetchpriority="high" decoding="async" src="../../../assets/p4a-map-card.webp" alt="Purple map artwork for $name civic architecture"></div>
      <div class="state-hero-content reveal">
        <p class="eyebrow">$short architecture builder</p>
        <h1>$name civic architecture</h1>
        <p>The $short layer starts with local communities, councils and bioregions, then uses state machinery as a coordination layer. The default drill-down should be local councils, with switchable lenses for state electorates, bioregions and First Nations nation or language maps.</p>
        <div class="research-badge"><span>Last research run</span><strong>$research</strong><small>$timezone</small></div>
      </div>
    </section>

    <section class="section state-summary-grid">
      <article class="summary-panel reveal">
        <p class="eyebrow">What belongs here</p>
        <h2>The map and tool layer.</h2>
        <p>Architecture is where $short decides how people move between community groups, councils, electorates, bioregions, protocol maps, public assets, local projects, public profile files, C-Hour contribution records, ledgers and simulations.</p>
        <p>It should show what data exists, what is missing, what can be updated from markdown, and which map lens is currently active.</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Not the constitution</p>
        <h2>Rules come next.</h2>
        <p>The constitution builder decides powers, limits, amendment pathways and legal commitments. This page designs the civic container those rules plug into.</p>
        <div class="button-row">
          <a class="button button-secondary" href="../constitution/index.html">Open $short constitution</a>
          <a class="button button-secondary" href="../index.html">Back to $short portal</a>
        </div>
      </article>
    </section>

    <section class="section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">State map builder</p>
          <h2>Default to councils, then switch lenses.</h2>
        </div>
        <p>The first proper state map should be clickable local councils. Electorates, bioregions and First Nations maps sit beside it as overlays, not replacements.</p>
      </div>
      <div class="map-builder reveal" data-map-layer-builder>
        <div class="segmented-control map-layer-controls" role="group" aria-label="$short architecture map layers">
          <button type="button" class="is-active" data-map-layer-choice="councils" aria-pressed="true">Local councils</button>
          <button type="button" data-map-layer-choice="electorates" aria-pressed="false">State electorates</button>
          <button type="button" data-map-layer-choice="bioregions" aria-pressed="false">Bioregions</button>
          <button type="button" data-map-layer-choice="first-nations" aria-pressed="false">First Nations maps</button>
        </div>
        <div class="map-builder-layout">
          <article class="map-builder-canvas">
            <span>$short</span>
            <h3 data-map-layer-title>Local councils layer</h3>
            <p data-map-layer-copy>Future SVG or GeoJSON council boundaries should render here first, then each council opens its own self-similar local portal.</p>
            <p class="map-data-target">Map data target: <code>assets/maps/$slug-councils.svg</code> or <code>content/local-councils/$slug.md</code></p>
          </article>
          <div class="map-layer-panels">
            <article class="map-layer-panel is-active" data-map-layer-panel="councils">
              <h3>Local councils first</h3>
              <p>Default drill-down: local government areas, wards where relevant, public assets, local laws, rates, grants, services, council meetings, local project boards, public/private markdown streams and C-Hour eligible contribution categories.</p>
              <ul class="plain-list">
                <li>Each council gets a portal, local ledger, local law memory, public noticeboard, public profile pattern and project board.</li>
                <li>Each council should eventually show care, repair, disaster response, mentoring, ecological work and civic service records only where consent and verification are clear.</li>
                <li>Future source suite: <code>content/local-councils/$slug.md</code>.</li>
              </ul>
            </article>
            <article class="map-layer-panel" data-map-layer-panel="electorates" hidden>
              <h3>State electorates</h3>
              <p>Electorates explain representation, campaigns, by-elections, local issues and who carries responsibility inside Parliament.</p>
              <ul class="plain-list">
                <li>Lower-house electorates are the default political accountability layer.</li>
                <li>Upper-house regions or councils need state-specific handling where they exist.</li>
              </ul>
            </article>
            <article class="map-layer-panel" data-map-layer-panel="bioregions" hidden>
              <h3>Bioregions and catchments</h3>
              <p>Living systems often explain reality better than political borders: water, food, fire, flood, coasts, islands, habitat and disaster corridors.</p>
              <ul class="plain-list">
                <li>This layer should connect ecological risk to councils and public assets.</li>
                <li>Future source suite: <code>content/bioregions/$slug.md</code>.</li>
              </ul>
            </article>
            <article class="map-layer-panel" data-map-layer-panel="first-nations" hidden>
              <h3>First Nations nation and language maps</h3>
              <p>This layer needs protocol, humility and source care. Public maps can guide learning, but they do not replace cultural authority or permission.</p>
              <ul class="plain-list">
                <li>Future pages should cite map provenance and show limits clearly.</li>
                <li><a href="https://aiatsis.gov.au/explore/map-indigenous-australia">AIATSIS map of Indigenous Australia</a> is a learning reference, not a local authority substitute.</li>
              </ul>
            </article>
          </div>
        </div>
      </div>
    </section>

    <section class="section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">Self-similar modules</p>
          <h2>Same pattern, state-specific contents.</h2>
        </div>
        <p>The state architecture should feel familiar without pretending every jurisdiction has the same laws, chambers, local government structure or cultural geography.</p>
      </div>
      <div class="feature-grid three reveal">
        <article><span class="card-number">01</span><h3>Overview</h3><p>Capital, current government, chamber type, council count, map sources, maintainers and last research run.</p></article>
        <article><span class="card-number">02</span><h3>Map stack</h3><p>Councils, wards, electorates, bioregions, First Nations maps, public assets and disaster-risk overlays.</p></article>
        <article><span class="card-number">03</span><h3>Tool stack</h3><p>Local portals, public profile.md files, self-sovereign digital twins, ledgers, Legal RAG references, project boards, civic surges, election clocks and simulation hooks.</p></article>
        <article><span class="card-number">04</span><h3>Braided economy</h3><p>C-Hour categories, verification rules, reciprocity ledgers and local public-good contribution need to sit inside the state architecture from the start.</p></article>
        <article><span class="card-number">05</span><h3>Public-private streams</h3><p>Public noticeboards and contribution leaderboards can be agent-readable markdown, while private notes, identity material and sensitive care context stay out of public views by default.</p></article>
        <article><span class="card-number">06</span><h3>Digital twins</h3><p>A diary, photo album and filing cabinet are analogue twins; profile.md suites are lightweight digital twins; Aura Genesis is one deeper pathway, not the only doorway.</p></article>
      </div>
    </section>

    <section class="section state-data-note reveal">
      <p class="eyebrow">Agent-ready data</p>
      <h2>This builder needs its own markdown suite.</h2>
      <p>Current state facts come from <code>$sourceMarkdown</code>. The next data layer should add council, electorate, bioregion, First Nations/protocol, public profile, public noticeboard, self-sovereign digital twin and contribution ledger markdown files so authorised agents can refresh maps without touching templates.</p>
      <p>$researchStatus</p>
    </section>
  </main>
  $footer
  <script src="../../../script.js?v=20260509-image-opt"></script>
</body>
</html>
"@

  Write-Utf8NoBom -Path (Join-Path $outDir "index.html") -Value $html
}

function Render-StateConstitutionPage {
  param(
    [object]$State,
    [string]$StateOutDir
  )

  $slug = [string]$State.slug
  $name = Escape-Html $State.name
  $short = Escape-Html $State.shortName
  $capital = Escape-Html $State.capital
  $stateType = Escape-Html $State.stateType
  $research = Escape-Html $State.researchRun
  $timezone = Escape-Html $State.researchTimezone
  $researchStatus = Escape-Html $State.researchStatus
  $sourceMarkdown = Escape-Html $State.sourceMarkdown
  $prefix = "../../../"
  $header = Get-Header -Prefix $prefix -Active "state-constitution" -CurrentStateSlug $slug -CurrentStateShort $short -CurrentStateType $stateType
  $layerStrip = Get-SiteLayerStrip -Prefix $prefix -Layer "state" -StateName $name -StateShort $short -StateType $stateType -StateSlug $slug
  $footer = Get-Foot -Prefix $prefix
  $outDir = Join-Path $StateOutDir "constitution"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  $html = @"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>P4A | $name constitution builder</title>
  <meta name="description" content="P4A $name constitution builder for state constitutional machinery, parliament, amendment pathways, local government powers, democratic checks and future civic reform.">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../../../assets/favicon.svg">
  <link rel="stylesheet" href="../../../styles.css?v=20260509-twinkle-video">
</head>
<body data-theme="royal" data-state-page="$slug-constitution">
  $header
  $layerStrip
  <main id="main" class="state-site-main builder-site-main">
    <section class="state-hero state-detail-hero">
      <div class="state-hero-bg"><img loading="eager" fetchpriority="high" decoding="async" src="../../../assets/p4a-map-card.webp" alt="Purple map artwork for $name constitution builder"></div>
      <div class="state-hero-content reveal">
        <p class="eyebrow">$short constitution builder</p>
        <h1>$name rulebook workbench</h1>
        <p>The $short constitution builder is not the national party constitution. It is a rulebook layer that should grow from local communities, councils and bioregions before it reaches state machinery: constitutional Acts, parliamentary structure, amendment paths, local government powers, democratic checks and what a future cyber-republic rehearsal would need to respect.</p>
        <div class="research-badge"><span>Last research run</span><strong>$research</strong><small>$timezone</small></div>
      </div>
    </section>

    <section class="section state-summary-grid">
      <article class="summary-panel reveal">
        <p class="eyebrow">What belongs here</p>
        <h2>Rules, powers and amendment paths.</h2>
        <p>This page should explain the $short constitutional machinery in plain English while staying rooted in the layers below it: community charters, council powers, public/private markdown rules, contribution ledger rules, parliament, executive government, courts and tribunals where relevant, electoral law, rights instruments if any, and how reform can lawfully happen.</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Architecture link</p>
        <h2>The map is next door.</h2>
        <p>The architecture builder handles communities, councils, electorates, bioregions, profile streams, public ledgers and map layers. This page handles what is binding, amendable, enforceable or only a proposal.</p>
        <div class="button-row">
          <a class="button button-secondary" href="../architecture/index.html">Open $short architecture</a>
          <a class="button button-secondary" href="../index.html">Back to $short portal</a>
        </div>
      </article>
    </section>

    <section class="section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">State-specific rule suite</p>
          <h2>Self-similar, not copy-paste.</h2>
        </div>
        <p>Every state and territory needs a constitution page, but the content must respect local charters and actual legal machinery rather than pretending the state is the first layer.</p>
      </div>
      <div class="constitution-grid reveal">
        <article class="track-card"><span>01</span><strong>Constitutional source</strong><p>Identify the constitutional Act, self-government Act or equivalent source of authority, with citations and plain-language notes.</p></article>
        <article class="track-card"><span>02</span><strong>Parliament and executive</strong><p>Explain chambers, ministries, Governor or Administrator roles, confidence, committees and scrutiny pathways.</p></article>
        <article class="track-card"><span>03</span><strong>Amendment pathway</strong><p>Show what can change by ordinary law, what needs referendum or special process, and what belongs to Commonwealth law.</p></article>
        <article class="track-card"><span>04</span><strong>Local government powers</strong><p>Connect councils to the state constitution, local government Acts, planning schemes, rates, public assets and local laws.</p></article>
        <article class="track-card"><span>05</span><strong>Rights and checks</strong><p>Map rights instruments, integrity bodies, ombudsman, audit offices, anti-corruption bodies, courts and human review.</p></article>
        <article class="track-card"><span>06</span><strong>Reform rehearsal</strong><p>Use simulations and version-controlled drafts before proposing legal change, so people can inspect consequences first.</p></article>
        <article class="track-card"><span>07</span><strong>C-Hour carve-out</strong><p>Separate verified public-good contribution from financial products, speculation and custodial crypto before any local pilot is proposed.</p></article>
        <article class="track-card"><span>08</span><strong>Braided economy limits</strong><p>Define verification, consent, anti-fraud review, local redemption, public ledger records and human governance before C-Hours touch real councils or assets.</p></article>
        <article class="track-card"><span>09</span><strong>Public profile rules</strong><p>Define what a public profile.md can show, what requires opt-in consent, what stays private and how contributors correct or withdraw public records.</p></article>
        <article class="track-card"><span>10</span><strong>Contribution leaderboard rules</strong><p>Let communities recognise useful work across money and C-Hours without turning care, identity or private life into a coercive score.</p></article>
      </div>
    </section>

    <section class="section state-summary-grid">
      <article class="summary-panel reveal">
        <p class="eyebrow">Braided economy foundation</p>
        <h2>Public-good work needs a lawful receipt.</h2>
        <p>The $short constitution builder should track what would be needed for a C-Hour or Community-Hour pilot: local government authority, state legislative limits, financial services boundaries, public-purpose verification, non-speculative design and community-level consent rules.</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Legal memory hook</p>
        <h2>Do not wing this bit.</h2>
        <p>The Legal RAG layer should hold the relevant Acts, regulator guidance, public-token arguments, council powers and state-local boundaries before any proposal claims it can operate.</p>
        <div class="button-row">
          <a class="button button-secondary" href="../../../pages/braided-economy.html">Braided Economy</a>
          <a class="button button-secondary" href="../../../pages/legal-rag.html">Law Engine</a>
          <a class="button button-secondary" href="../../../pages/civic-ledger.html">Civic ledger</a>
        </div>
      </article>
    </section>

    <section class="section state-summary-grid">
      <article class="summary-panel reveal">
        <p class="eyebrow">Gamification line</p>
        <h2>Leaderboards need limits.</h2>
        <p>Public noticeboards, profile.md files and community contribution leaderboards can help $short communities see useful work, but the rules must separate public recognition from private context, identity data, care records and sensitive financial detail.</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Process compatibility</p>
        <h2>Aura Genesis is optional infrastructure.</h2>
        <p>Aura Genesis can inform the profile, ledger and contribution workflow as one intensive self-sovereign digital-twin pathway, including many .md files from a 60 by 2-hour HBOT-chamber practice. It is not exclusive: councils, bioregions and community groups should be able to build lighter markdown twins, rename, fork, simplify or replace the process while keeping the same public/private safeguards.</p>
      </article>
    </section>

    <section class="section state-notes-sources">
      <article class="summary-panel reveal">
        <p class="eyebrow">Current data</p>
        <h2>Start from the state markdown.</h2>
        <p>Current political and chamber data comes from <code>$sourceMarkdown</code>. The constitution builder should later get its own source file at <code>content/constitutions/$slug.md</code>.</p>
        <p>$researchStatus</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Builder warning</p>
        <h2>No fake authority.</h2>
        <p>This page is a civic literacy and drafting workbench. It should not present proposals as law, legal advice or adopted policy. Every claim needs sources, version history and room for correction.</p>
      </article>
    </section>
  </main>
  $footer
  <script src="../../../script.js?v=20260509-image-opt"></script>
</body>
</html>
"@

  Write-Utf8NoBom -Path (Join-Path $outDir "index.html") -Value $html
}

function Render-StateMap {
  param(
    [array]$States,
    [string]$Prefix
  )

  $shapeBySlug = @{
    wa  = @{ pathId = "path12"; x = 94; y = 178 }
    nt  = @{ pathId = "path10"; x = 226; y = 112 }
    qld = @{ pathId = "path22"; x = 360; y = 132 }
    sa  = @{ pathId = "path18"; x = 247; y = 244 }
    nsw = @{ pathId = "path16"; x = 358; y = 286 }
    vic = @{ pathId = "path20"; x = 340; y = 346 }
    tas = @{ pathId = "path26"; x = 371; y = 396 }
    act = @{ pathId = "path14"; x = 401; y = 316 }
  }

  $links = foreach ($state in $States) {
    $slug = [string]$state.slug
    $shape = $shapeBySlug[$slug]
    if ($null -eq $shape) { continue }
    $href = Get-StateHref -Prefix $Prefix -Slug $slug
    $label = Escape-Html ("Open " + $state.name + " portal")
    $short = Escape-Html $state.shortName
    $pathId = $shape.pathId
    $x = $shape.x
    $y = $shape.y
    $sourceHref = "${Prefix}assets/australian-states-map-wikipedia.svg#$pathId"
@"
<a href="$href" class="state-map-link" data-map-state="$slug" aria-label="$label">
  <use class="state-shape" href="$sourceHref"></use>
  <text x="$x" y="$y" text-anchor="middle">$short</text>
</a>
"@
  }

@"
<svg class="australia-state-map" viewBox="0 0 460 420" role="img" aria-labelledby="state-map-title state-map-desc">
  <title id="state-map-title">Interactive state and territory map of Australia</title>
  <desc id="state-map-desc">Select a state or territory to open its P4A portal page.</desc>
  $($links -join "`n")
</svg>
<p class="state-map-source">Map geometry: <a href="https://commons.wikimedia.org/wiki/File:Australian_states_map.svg" target="_blank" rel="noopener">Australian states map.svg</a>, Wikimedia Commons, CC0.</p>
"@
}

function Get-HistoryHref {
  param(
    [string]$Prefix,
    [string]$Slug
  )
  return "${Prefix}states/${Slug}/history/index.html"
}

function Get-HistoryThemeLabel {
  param(
    [object]$History,
    [string]$ThemeId
  )

  foreach ($theme in @($History.themes)) {
    if ([string]$theme.id -eq $ThemeId) {
      return [string]$theme.label
    }
  }
  return $ThemeId
}

function Render-HistoryControls {
  param(
    [string]$Label,
    [array]$Themes
  )

  $safeLabel = Escape-Html $Label
  $themeOptions = foreach ($theme in @($Themes)) {
    $id = Escape-Html $theme.id
    $label = Escape-Html $theme.label
    "<option value=""$id"">$label</option>"
  }

@"
<div class="history-controls" data-history-controls aria-label="$safeLabel history controls">
  <label class="timer-sort-label">
    <span>Sort history</span>
    <select data-history-sort>
      <option value="oldest">Oldest first</option>
      <option value="newest">Newest first</option>
      <option value="state">State A-Z</option>
      <option value="theme">Theme A-Z</option>
      <option value="period">Period A-Z</option>
    </select>
  </label>
  <label class="timer-sort-label">
    <span>History layer</span>
    <select data-history-level>
      <option value="basic">Basic path</option>
      <option value="advanced">Advanced layer</option>
      <option value="all">All layers</option>
    </select>
  </label>
  <label class="timer-sort-label">
    <span>Theme</span>
    <select data-history-theme>
      <option value="all">All themes</option>
      $($themeOptions -join "`n      ")
    </select>
  </label>
  <label class="timer-sort-label history-search-label">
    <span>Search</span>
    <input type="search" data-history-search placeholder="Search events, periods or sources">
  </label>
</div>
"@
}

function Render-HistoryCard {
  param(
    [object]$History,
    [object]$Event,
    [string]$ExtraClass = ""
  )

  $slug = Escape-Html $History.slug
  $stateName = Escape-Html $History.stateName
  $shortName = Escape-Html $History.shortName
  $sortYear = Escape-Html $Event.sortYear
  $dateLabel = Escape-Html $Event.dateLabel
  $period = Escape-Html $Event.period
  $level = Escape-Html $Event.level
  $title = Escape-Html $Event.title
  $summary = Escape-Html $Event.summary
  $advanced = Escape-Html $Event.advanced
  $difference = Escape-Html $Event.difference
  $themeIds = @($Event.themes) | ForEach-Object { [string]$_ }
  $themeData = Escape-Html ($themeIds -join ",")
  $themeTags = foreach ($themeId in $themeIds) {
    $themeLabel = Escape-Html (Get-HistoryThemeLabel -History $History -ThemeId $themeId)
    "<span>$themeLabel</span>"
  }
  $sourceItems = foreach ($source in @($Event.sources)) {
    $label = Escape-Html $source.label
    $url = Escape-Html $source.url
    "<li><a href=""$url"">$label</a></li>"
  }

  $advancedBlock = ""
  if (-not [string]::IsNullOrWhiteSpace([string]$Event.advanced) -or -not [string]::IsNullOrWhiteSpace([string]$Event.difference)) {
    $differencePara = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$Event.difference)) {
      $differencePara = "<p><strong>State difference:</strong> $difference</p>"
    }
    $advancedPara = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$Event.advanced)) {
      $advancedPara = "<p><strong>Advanced:</strong> $advanced</p>"
    }
    $advancedBlock = @"
  <details class="history-advanced">
    <summary>Advanced layer</summary>
    $advancedPara
    $differencePara
  </details>
"@
  }

@"
<article class="history-card $ExtraClass" data-history-card data-state="$slug" data-history-sort-year="$sortYear" data-history-period="$period" data-history-level="$level" data-history-themes="$themeData" data-history-title="$title">
  <div class="history-card-topline">
    <span>$shortName</span>
    <span>$period</span>
  </div>
  <p class="history-date">$dateLabel</p>
  <h3>$title</h3>
  <p>$summary</p>
  <div class="history-tags" aria-label="History themes">
    $($themeTags -join "`n    ")
  </div>
  $advancedBlock
  <ul class="history-source-list">
    $($sourceItems -join "`n    ")
  </ul>
  <span class="history-state-name">$stateName</span>
</article>
"@
}

function Render-HistoryCards {
  param(
    [object]$History,
    [string]$ExtraClass = ""
  )

  $cards = foreach ($event in @($History.events)) {
    Render-HistoryCard -History $History -Event $event -ExtraClass $ExtraClass
  }
  return ($cards -join "`n")
}

function Render-AllHistoryCards {
  param([array]$Histories)

  $cards = foreach ($history in @($Histories)) {
    foreach ($event in @($history.events)) {
      Render-HistoryCard -History $history -Event $event -ExtraClass "history-index-event"
    }
  }
  return ($cards -join "`n")
}

function Render-HistoryIndexCards {
  param([array]$Histories)

  $cards = foreach ($history in @($Histories)) {
    $slug = Escape-Html $history.slug
    $href = Get-HistoryHref -Prefix "../" -Slug $slug
    $name = Escape-Html $history.stateName
    $short = Escape-Html $history.shortName
    $stateType = Escape-Html $history.stateType
    $hint = Escape-Html $history.differenceHint
    $basicCount = @($history.events | Where-Object { [string]$_.level -eq "basic" }).Count
    $advancedCount = @($history.events | Where-Object { [string]$_.level -eq "advanced" }).Count
    $research = Escape-Html $history.researchRun
@"
<a class="history-index-card" href="$href" data-state="$slug">
  <span>$short</span>
  <h3>$name</h3>
  <p>$stateType history portal</p>
  <strong>$basicCount basic events, $advancedCount advanced events</strong>
  <small>$hint</small>
  <em>Research run: $research</em>
</a>
"@
  }

  return ($cards -join "`n")
}

function Render-HistorySources {
  param([object]$History)

  $items = foreach ($source in @($History.sources)) {
    $label = Escape-Html $source.label
    $url = Escape-Html $source.url
    "<li><a href=""$url"">$label</a></li>"
  }
  return ($items -join "`n")
}

$states = @(Get-StateData | Sort-Object order)
if ($states.Count -eq 0) {
  throw "No state data found in $contentDir"
}

$historyItems = @(Get-HistoryData | Sort-Object order)

New-Item -ItemType Directory -Force -Path $pagesDir, $statesDir, $assetsDir | Out-Null

$json = $states | ConvertTo-Json -Depth 30
Write-Utf8NoBom -Path (Join-Path $assetsDir "state-data.js") -Value "window.P4A_STATE_DATA = $json;"

if ($historyItems.Count -gt 0) {
  $historyJson = $historyItems | ConvertTo-Json -Depth 40
  Write-Utf8NoBom -Path (Join-Path $assetsDir "history-data.js") -Value "window.P4A_HISTORY_DATA = $historyJson;"
}

$researchRun = Escape-Html $states[0].researchRun
$researchTz = Escape-Html $states[0].researchTimezone
$portalHeader = Get-Header -Prefix "../" -Active "states"
$portalLayerStrip = Get-SiteLayerStrip -Prefix "../" -Layer "national"
$portalFooter = Get-Foot -Prefix "../"
$map = Render-StateMap -States $states -Prefix "../"
$allTimers = Render-AllElectionCards -States $states -ExtraClass "portal-timer"
$portalTimerControls = Render-TimerControls -Label "National"
$stateCards = foreach ($state in $states) {
  $slug = Escape-Html $state.slug
  $href = Get-StateHref -Prefix "../" -Slug $slug
  $name = Escape-Html $state.name
  $short = Escape-Html $state.shortName
  $capital = Escape-Html $state.capital
  $status = Escape-Html $state.researchStatus
  $gov = Escape-Html ($state.government.party + " - " + $state.government.arrangement)
  $nextElection = @($state.elections | Where-Object { $_.scope -eq "general" } | Select-Object -First 1)[0]
  $nextLabel = if ($null -ne $nextElection) { Escape-Html ($nextElection.label + " - " + (Format-DateLabel $nextElection.date)) } else { "No election date recorded" }
@"
<a class="state-portal-card" href="$href" data-state="$slug">
  <span>$short</span>
  <h3>$name</h3>
  <p>$capital</p>
  <strong>$gov</strong>
  <small>$nextLabel</small>
  <em>$status</em>
</a>
"@
}

$portalHtml = @"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>P4A | State and territory portals</title>
  <meta name="description" content="P4A state and territory portal with live election countdowns, chamber data and state-level civic simulator entry points.">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../assets/favicon.svg">
  <link rel="stylesheet" href="../styles.css?v=20260509-twinkle-video">
</head>
<body data-theme="royal" data-state-page="portal">
  $portalHeader
  $portalLayerStrip
  <main id="main" class="state-site-main">
    <section class="state-hero state-portal-hero">
      <div class="state-hero-bg"><img loading="eager" fetchpriority="high" decoding="async" src="../assets/p4a-map-card.webp" alt="Purple Australia map artwork"></div>
      <div class="state-hero-content reveal">
        <p class="eyebrow">State layer unlocked</p>
        <h1>Eight local doors into the purple republic rehearsal.</h1>
        <p>p4A starts national, but the work becomes real state by state: who holds power, how the chambers split, when voters next move, and where a cyber-republic referendum simulator needs local proof before 2032.</p>
        <div class="research-badge"><span>Last research run</span><strong>$researchRun</strong><small>$researchTz</small></div>
      </div>
    </section>

    <section class="section state-map-section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">Touch the map</p>
          <h2>Choose a state or territory.</h2>
        </div>
        <p>Each jurisdiction opens a local clone with current power, chamber and election data.</p>
      </div>
      <div class="state-map-layout reveal">
        <div class="state-map-panel">
          $map
        </div>
        <div class="state-card-grid">
          $($stateCards -join "`n")
        </div>
      </div>
    </section>

    <section class="section countdown-section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">Election clocks</p>
          <h2>Election timers and by-elections.</h2>
        </div>
        <p>Timers point to scheduled or last-possible election dates where available. Each card carries days-until, days-since and the archive cycle from the markdown data.</p>
      </div>
      <div class="timer-module reveal" data-timer-module>
        $portalTimerControls
        <div class="timer-grid" data-timer-board>
          $allTimers
        </div>
        <p class="timer-empty" data-timer-empty hidden>No timers match this filter.</p>
      </div>
    </section>

    <section class="section state-data-note reveal">
      <p class="eyebrow">Agent-ready data</p>
      <h2>The facts live in markdown.</h2>
      <p>Each state clone is generated from a simple file in <code>content/states/</code>. State history pages come from <code>content/history/</code>. Future authorised agents can update those files, rerun the build script, and the public pages will follow.</p>
      <div class="button-row">
        <a class="button button-secondary" href="state-history.html">Open state histories</a>
      </div>
    </section>
  </main>
  $portalFooter
  <script src="../assets/state-data.js?v=20260509-pills"></script>
  <script src="../script.js?v=20260509-image-opt"></script>
</body>
</html>
"@

Write-Utf8NoBom -Path (Join-Path $pagesDir "states.html") -Value $portalHtml

if ($historyItems.Count -gt 0) {
  $historyThemeLookup = @{}
  foreach ($history in $historyItems) {
    foreach ($theme in @($history.themes)) {
      $themeId = [string]$theme.id
      if (-not $historyThemeLookup.ContainsKey($themeId)) {
        $historyThemeLookup[$themeId] = $theme
      }
    }
  }
  $historyThemes = @($historyThemeLookup.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
  $historyResearchRun = Escape-Html $historyItems[0].researchRun
  $historyResearchTz = Escape-Html $historyItems[0].researchTimezone
  $historyHeader = Get-Header -Prefix "../" -Active "histories"
  $historyLayerStrip = Get-SiteLayerStrip -Prefix "../" -Layer "national"
  $historyFooter = Get-Foot -Prefix "../"
  $historyIndexCards = Render-HistoryIndexCards -Histories $historyItems
  $historyControls = Render-HistoryControls -Label "State history index" -Themes $historyThemes
  $historyTimeline = Render-AllHistoryCards -Histories $historyItems

  $historyIndexHtml = @"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>P4A | State history atlas</title>
  <meta name="description" content="P4A state and territory history atlas generated from markdown files with basic and advanced civic history layers.">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../assets/favicon.svg">
  <link rel="stylesheet" href="../styles.css?v=20260509-twinkle-video">
</head>
<body data-theme="royal" data-state-page="history-index">
  $historyHeader
  $historyLayerStrip
  <main id="main" class="state-site-main history-site-main">
    <section class="state-hero history-hero">
      <div class="state-hero-bg"><img loading="eager" fetchpriority="high" decoding="async" src="../assets/p4a-map-card.webp" alt="Purple Australia map artwork"></div>
      <div class="state-hero-content reveal">
        <p class="eyebrow">History atlas</p>
        <h1>How each state became different.</h1>
        <p>The portals now carry a history layer: basic public timelines, advanced constitutional detail, state-specific differences and source links that future authorised agents can refresh from markdown.</p>
        <div class="research-badge"><span>Last research run</span><strong>$historyResearchRun</strong><small>$historyResearchTz</small></div>
      </div>
    </section>

    <section class="section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">State history doors</p>
          <h2>Open a local history portal.</h2>
        </div>
        <p>Each card links to the history page inside that state or territory clone, keeping the national layer and state layer distinct before future council layers arrive.</p>
      </div>
      <div class="history-index-grid reveal">
        $historyIndexCards
      </div>
    </section>

    <section class="section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">Compare timelines</p>
          <h2>Sort basic and advanced history.</h2>
        </div>
        <p>Start with the basic path, then switch to advanced to see the constitutional machinery, franchise changes, chamber reforms and territory-state differences.</p>
      </div>
      <div class="history-module reveal" data-history-module>
        $historyControls
        <p class="history-count" data-history-count>Checking history events...</p>
        <div class="history-grid" data-history-board>
          $historyTimeline
        </div>
        <p class="timer-empty" data-history-empty hidden>No history events match this filter.</p>
      </div>
    </section>

    <section class="section state-data-note reveal">
      <p class="eyebrow">Agent-ready history</p>
      <h2>The timeline lives in markdown.</h2>
      <p>Source files are in <code>content/history/</code>. Each event has a sort year, layer, period, themes, source links and advanced notes so future agents can update the record without touching the page template.</p>
    </section>
  </main>
  $historyFooter
  <script src="../assets/history-data.js?v=20260509-pills"></script>
  <script src="../script.js?v=20260509-image-opt"></script>
</body>
</html>
"@

  Write-Utf8NoBom -Path (Join-Path $pagesDir "state-history.html") -Value $historyIndexHtml
}

foreach ($state in $states) {
  $slug = [string]$state.slug
  $stateOutDir = Join-Path $statesDir $slug
  New-Item -ItemType Directory -Force -Path $stateOutDir | Out-Null

  $prefix = "../../"
  $name = Escape-Html $state.name
  $short = Escape-Html $state.shortName
  $capital = Escape-Html $state.capital
  $stateType = Escape-Html $state.stateType
  $header = Get-Header -Prefix $prefix -Active "state-local" -CurrentStateSlug $slug -CurrentStateShort $short -CurrentStateType $stateType
  $stateLayerStrip = Get-SiteLayerStrip -Prefix $prefix -Layer "state" -StateName $name -StateShort $short -StateType $stateType -StateSlug $slug
  $footer = Get-Foot -Prefix $prefix
  $research = Escape-Html $state.researchRun
  $timezone = Escape-Html $state.researchTimezone
  $researchStatus = Escape-Html $state.researchStatus
  $timerControls = Render-TimerControls -Label $short
  $leaderTitle = Escape-Html $state.government.leaderTitle
  $leader = Escape-Html $state.government.leader
  $govParty = Escape-Html $state.government.party
  $arrangement = Escape-Html $state.government.arrangement
  $inPower = Escape-Html $state.government.inPowerSince
  $govNote = Escape-Html $state.government.note
  $timers = Render-ElectionCards -State $state -ExtraClass "state-page-timer"
  $chambers = Render-Chambers -State $state
  $sources = Render-Sources -State $state
  $notes = Render-StrategyNotes -State $state
  $sourceMarkdown = Escape-Html $state.sourceMarkdown
  $stateMapLink = "../$slug/index.html"

  $stateHtml = @"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>P4A | $name portal</title>
  <meta name="description" content="P4A $name state portal with election countdowns, chamber composition and current government notes.">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../../assets/favicon.svg">
  <link rel="stylesheet" href="../../styles.css?v=20260509-twinkle-video">
</head>
<body data-theme="royal" data-state-page="$slug">
  $header
  $stateLayerStrip
  <main id="main" class="state-site-main">
    <section class="state-hero state-detail-hero">
      <div class="state-hero-bg"><img loading="eager" fetchpriority="high" decoding="async" src="../../assets/p4a-map-card.webp" alt="Purple Australia map artwork"></div>
      <div class="state-hero-content reveal">
        <p class="eyebrow">$stateType portal</p>
        <h1>$name</h1>
        <p>$short starts from $capital and works outward: current power, chamber balance, election clocks and the local civic rehearsal layer that can plug back into the national P4A preframe.</p>
        <div class="research-badge"><span>Last research run</span><strong>$research</strong><small>$timezone</small></div>
      </div>
    </section>

    <section class="section state-summary-grid">
      <article class="summary-panel reveal">
        <p class="eyebrow">Who is in power</p>
        <h2>$leaderTitle $leader</h2>
        <dl class="fact-list">
          <div><dt>Government</dt><dd>$govParty</dd></div>
          <div><dt>Arrangement</dt><dd>$arrangement</dd></div>
          <div><dt>In power since</dt><dd>$inPower</dd></div>
        </dl>
        <p>$govNote</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Research status</p>
        <h2>Checked $research</h2>
        <p>$researchStatus</p>
        <p>Editable source: <code>$sourceMarkdown</code></p>
        <div class="button-row">
          <a class="button button-secondary" href="architecture/index.html">Open $short architecture</a>
          <a class="button button-secondary" href="constitution/index.html">Open $short constitution</a>
          <a class="button button-secondary" href="../../index.html">Back to national page</a>
          <a class="button button-secondary" href="../../pages/states.html">Back to state map</a>
          <a class="button button-secondary" href="history/index.html">Open state history</a>
        </div>
      </article>
    </section>

    <section class="section countdown-section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">$short timers</p>
          <h2>Election timers.</h2>
        </div>
        <p>Scheduled, expected, recent or last-possible dates are labelled directly on each card, including days-until, days-since and the markdown archive rule.</p>
      </div>
      <div class="timer-module reveal" data-timer-module>
        $timerControls
        <div class="timer-grid" data-timer-board>
          $timers
        </div>
        <p class="timer-empty" data-timer-empty hidden>No timers match this filter.</p>
      </div>
    </section>

    <section class="section chamber-section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">Chamber split</p>
          <h2>Party seats and named crossbench.</h2>
        </div>
        <p>These totals are the data layer future agents should refresh when resignations, recounts or by-elections change the map.</p>
      </div>
      <div class="chamber-grid reveal">
        $chambers
      </div>
    </section>

    <section class="section state-notes-sources">
      <article class="summary-panel reveal">
        <p class="eyebrow">Tailoring notes</p>
        <h2>How this clone should think.</h2>
        <ul class="plain-list">
          $notes
        </ul>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Sources</p>
        <h2>Research links.</h2>
        <ul class="source-list">
          $sources
        </ul>
      </article>
    </section>
  </main>
  $footer
  <script src="../../assets/state-data.js?v=20260509-pills"></script>
  <script src="../../script.js?v=20260509-image-opt"></script>
</body>
</html>
"@

  Write-Utf8NoBom -Path (Join-Path $stateOutDir "index.html") -Value $stateHtml
  Render-StateArchitecturePage -State $state -StateOutDir $stateOutDir
  Render-StateConstitutionPage -State $state -StateOutDir $stateOutDir

  if ($historyItems.Count -gt 0) {
    $history = @($historyItems | Where-Object { [string]$_.slug -eq $slug } | Select-Object -First 1)[0]
    if ($null -ne $history) {
      $historyOutDir = Join-Path $stateOutDir "history"
      New-Item -ItemType Directory -Force -Path $historyOutDir | Out-Null

      $historyPrefix = "../../../"
      $historyHeaderLocal = Get-Header -Prefix $historyPrefix -Active "state-history" -CurrentStateSlug $slug -CurrentStateShort $short -CurrentStateType $stateType
      $historyLayerStripLocal = Get-SiteLayerStrip -Prefix $historyPrefix -Layer "state" -StateName $name -StateShort $short -StateType $stateType -StateSlug $slug
      $historyFooterLocal = Get-Foot -Prefix $historyPrefix
      $historyResearch = Escape-Html $history.researchRun
      $historyTimezone = Escape-Html $history.researchTimezone
      $historyStatus = Escape-Html $history.researchStatus
      $historySummary = Escape-Html $history.summary
      $historyHint = Escape-Html $history.differenceHint
      $historyBasic = Escape-Html $history.basicThesis
      $historyAdvanced = Escape-Html $history.advancedThesis
      $historySourceMarkdown = Escape-Html $history.sourceMarkdown
      $historyTimelineControls = Render-HistoryControls -Label $short -Themes $history.themes
      $historyCards = Render-HistoryCards -History $history
      $historySources = Render-HistorySources -History $history

      $historyHtml = @"
<!doctype html>
<html lang="en-AU">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>P4A | $name history</title>
  <meta name="description" content="P4A $name history page with basic and advanced civic timelines generated from markdown data.">
  <meta name="theme-color" content="#3F0F75">
  <link rel="icon" type="image/svg+xml" href="../../../assets/favicon.svg">
  <link rel="stylesheet" href="../../../styles.css?v=20260509-twinkle-video">
</head>
<body data-theme="royal" data-state-page="$slug-history">
  $historyHeaderLocal
  $historyLayerStripLocal
  <main id="main" class="state-site-main history-site-main">
    <section class="state-hero history-hero">
      <div class="state-hero-bg"><img loading="eager" fetchpriority="high" decoding="async" src="../../../assets/p4a-map-card.webp" alt="Purple Australia map artwork"></div>
      <div class="state-hero-content reveal">
        <p class="eyebrow">$stateType history portal</p>
        <h1>$name history</h1>
        <p>$historySummary</p>
        <div class="research-badge"><span>Last research run</span><strong>$historyResearch</strong><small>$historyTimezone</small></div>
      </div>
    </section>

    <section class="section state-summary-grid">
      <article class="summary-panel reveal">
        <p class="eyebrow">Basic path</p>
        <h2>What most people need first.</h2>
        <p>$historyBasic</p>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Advanced layer</p>
        <h2>The machinery underneath.</h2>
        <p>$historyAdvanced</p>
        <p><strong>State difference:</strong> $historyHint</p>
      </article>
    </section>

    <section class="section">
      <div class="section-heading reveal">
        <div>
          <p class="eyebrow">$short timeline</p>
          <h2>Basic and advanced history.</h2>
        </div>
        <p>Use the controls to move between a simple public timeline and the deeper constitutional, electoral and parliamentary context.</p>
      </div>
      <div class="history-module reveal" data-history-module>
        $historyTimelineControls
        <p class="history-count" data-history-count>Checking history events...</p>
        <div class="history-grid" data-history-board>
          $historyCards
        </div>
        <p class="timer-empty" data-history-empty hidden>No history events match this filter.</p>
      </div>
    </section>

    <section class="section state-notes-sources">
      <article class="summary-panel reveal">
        <p class="eyebrow">Research status</p>
        <h2>Checked $historyResearch</h2>
        <p>$historyStatus</p>
        <p>Editable source: <code>$historySourceMarkdown</code></p>
        <div class="button-row">
          <a class="button button-secondary" href="../index.html">Back to $short portal</a>
          <a class="button button-secondary" href="../architecture/index.html">$short architecture</a>
          <a class="button button-secondary" href="../constitution/index.html">$short constitution</a>
          <a class="button button-secondary" href="../../../pages/state-history.html">All state histories</a>
          <a class="button button-secondary" href="../../../index.html">National page</a>
        </div>
      </article>
      <article class="summary-panel reveal">
        <p class="eyebrow">Sources</p>
        <h2>Research links.</h2>
        <ul class="source-list">
          $historySources
        </ul>
      </article>
    </section>
  </main>
  $historyFooterLocal
  <script src="../../../assets/history-data.js?v=20260509-pills"></script>
  <script src="../../../script.js?v=20260509-image-opt"></script>
</body>
</html>
"@

      Write-Utf8NoBom -Path (Join-Path $historyOutDir "index.html") -Value $historyHtml
    }
  }
}

Write-Host "Generated $($states.Count) state portals, $($historyItems.Count) history portals, pages/states.html and pages/state-history.html"

