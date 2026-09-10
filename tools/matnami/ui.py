import json
from typing import List
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.syntax import Syntax
from rich.text import Text

from .models import AuditReport, IntelligenceReport

console = Console()

def print_banner():
    banner = """[bold red]
 ███    ███  █████  ████████ ███    ██  █████  ███    ███ ██ 
 ████  ████ ██   ██    ██    ████   ██ ██   ██ ████  ████ ██ 
 ██ ████ ██ ███████    ██    ██ ██  ██ ███████ ██ ████ ██ ██ 
 ██  ██  ██ ██   ██    ██    ██  ██ ██ ██   ██ ██  ██  ██ ██ 
 ██      ██ ██   ██    ██    ██   ████ ██   ██ ██      ██ ██ 
[/bold red]
[bold cyan]Matnami Source Tester & Compatibility Auditor for iPad Air 1 (iOS 12)[/bold cyan]
[dim]Download-First Architecture • Hardware H.264 VDA • Anti-Jetsam Safe (< 180MB RAM)[/dim]
"""
    console.print(banner)

def display_audit_report(report: AuditReport):
    console.print("\n")
    # Title Panel
    status_text = "[bold green]COMPATIBLE WITH IPAD AIR 1[/bold green]" if report.is_compatible else "[bold red]STRICT REJECTION / INCOMPATIBLE[/bold red]"
    console.print(Panel(
        f"[bold white]Target Website:[/] [cyan]{report.url}[/]  |  [bold white]CMS:[/] [yellow]{report.cms_detected}[/]\n"
        f"[bold white]Overall Score:[/] [magenta]{report.overall_score}/100[/]  |  [bold white]Verdict:[/] {status_text}\n"
        f"[bold white]Edge Proxy Required:[/] {'[yellow]YES (Cloudflare Protected)[/]' if report.use_proxy else '[green]NO (Direct Access)[/]'}",
        title=f"[bold]Compatibility Audit: {report.source_name}[/bold]",
        border_style="red" if not report.is_compatible else "green"
    ))

    # Hops Table
    table = Table(title="Hop-by-Hop Breakdown (3-Hop Traversal + Codec Check)", show_header=True, header_style="bold cyan")
    table.add_column("Hop", style="dim", width=6)
    table.add_column("Stage Name", style="bold", width=22)
    table.add_column("Status", width=12)
    table.add_column("Score", width=8, justify="right")
    table.add_column("Diagnostics & Findings")

    hops = [
        ("Hop 0", report.network_hop),
        ("Hop 1", report.catalog_hop),
        ("Hop 2", report.detail_hop),
        ("Hop 3", report.servers_hop)
    ]

    for hop_id, hop in hops:
        status_str = "[bold green]PASS[/bold green]" if hop.passed else "[bold red]FAIL[/bold red]"
        score_str = f"{hop.score}/{hop.max_score}"
        msgs = " • ".join(hop.messages) if hop.messages else (hop.error or "None")
        table.add_row(hop_id, hop.name, status_str, score_str, msgs)

    console.print(table)

    # Language Audit Panel
    if report.language_audit:
        la = report.language_audit
        border = "green" if la.is_acceptable else "red"
        console.print(Panel(
            f"[bold white]Detected Languages:[/] {', '.join(la.detected_languages) if la.detected_languages else '[dim]None verified[/dim]'}\n"
            f"[bold white]English Subtitles:[/] {'[green]YES (Supported)[/]' if la.has_english_sub else '[yellow]NO[/]'}\n"
            f"[bold white]English Dubbed:[/] {'[green]YES (Supported)[/]' if la.has_english_dub else '[yellow]NO[/]'}\n"
            f"[bold white]Language Rubric Status:[/] {la.status}",
            title="[bold]Audio & Subtitle Language Audit (Japanese + Eng Sub OR Eng Dub/Sub)[/bold]",
            border_style=border
        ))

    # Video Stream Audit Table
    if report.stream_audit:
        s = report.stream_audit
        s_table = Table(title="Video Stream Audit for iPad Air 1 (iOS 12.5.7)", show_header=True, header_style="bold magenta")
        s_table.add_column("Attribute", style="bold", width=22)
        s_table.add_column("Value")
        s_table.add_column("iOS 12 Verdict", width=16)

        s_table.add_row("Primary Server", s.server_name, "[green]OK[/]")
        s_table.add_row("Stream URL", s.url[:70] + "..." if len(s.url) > 70 else s.url, "[dim]Inspected[/]")
        s_table.add_row("HTTP Status", str(s.status_code), "[green]PASS[/]" if s.status_code in (200, 206) else "[red]FAIL[/]")
        s_table.add_row("Byte Range (206)", "Supported" if s.supports_byte_range else "Not Supported", "[green]PASS[/]" if s.supports_byte_range else "[yellow]WARN[/]")
        
        hw_verdict = "[bold green]100% HW VDA[/]" if s.is_hw_accelerated else "[bold red]REJECT (No HW)[/]"
        s_table.add_row("Codec & Profile", s.codec, hw_verdict)
        s_table.add_row("Download Throughput", f"{s.speed_mbps:.1f} Mbps", "[green]FAST[/]" if s.speed_mbps > 5 else "[yellow]FAIR[/]")

        console.print(s_table)

    # Intelligent Decision Tree & Heuristics Breakdown
    if report.intelligence:
        display_intelligence_tree(report.intelligence)

    # Recommendations
    if report.recommendations:
        console.print("\n[bold yellow]Auditor Recommendations & Diagnostics:[/bold yellow]")
        for rec in report.recommendations:
            console.print(f"  [yellow]•[/yellow] {rec}")

    # Suggested sources.json configuration
    if report.suggested_config:
        console.print("\n[bold cyan]Generated sources.json Configuration:[/bold cyan]")
        formatted_json = json.dumps(report.suggested_config, indent=2)
        syntax = Syntax(formatted_json, "json", theme="monokai", line_numbers=False)
        console.print(syntax)

def display_intelligence_tree(intel: IntelligenceReport):
    if not intel:
        return

    console.print("\n")
    # Intelligence Decision Tree Table
    t_intel = Table(
        title="Heuristics & Decision Tree Evaluation Engine (if/else Reasoning)",
        show_header=True,
        header_style="bold yellow"
    )
    t_intel.add_column("Rule / Heuristic", style="bold cyan", width=22)
    t_intel.add_column("Evaluated Condition (IF)", style="white", width=36)
    t_intel.add_column("Decision Outcome (THEN)", style="yellow", width=30)
    t_intel.add_column("Status", width=10, justify="center")
    t_intel.add_column("Architectural Deduction", style="dim")

    for rule in intel.decision_rules:
        if rule.status == "PASS":
            st_text = "[bold green]PASS[/bold green]"
        elif rule.status == "FAIL":
            st_text = "[bold red]FAIL[/bold red]"
        elif rule.status == "WARN":
            st_text = "[bold yellow]WARN[/bold yellow]"
        else:
            st_text = "[dim]SKIP[/dim]"

        t_intel.add_row(
            rule.rule_name,
            rule.condition,
            rule.outcome,
            st_text,
            rule.deduction
        )

    console.print(t_intel)

    # Synthesis & Architectural Advice Panel
    border = "red" if intel.is_fundamental_rejection else ("green" if "100% COMPATIBLE" in intel.verdict_summary else "yellow")
    
    proxy_str = "[bold green]YES (Edge Worker can bypass)[/bold green]" if intel.can_be_fixed_with_proxy else "[dim]NO[/dim]"
    fund_str = "[bold red]YES (Unusable on iPad Air 1)[/bold red]" if intel.is_fundamental_rejection else "[bold green]NO[/bold green]"

    content = [
        f"[bold white]Executive Verdict:[/] {intel.verdict_summary}",
        f"[bold white]Proxy Solvable?[/] {proxy_str}  |  [bold white]Fundamental Rejection?[/] {fund_str}\n"
    ]
    if intel.architectural_advice:
        content.append("[bold white]Architectural Guidance & Next Steps:[/bold white]")
        for adv in intel.architectural_advice:
            content.append(f"  [cyan]•[/cyan] {adv}")

    console.print(Panel(
        "\n".join(content),
        title="[bold]Synthesized Auditor Intelligence & Architecture Advice[/bold]",
        border_style=border
    ))

def display_batch_summary_table(reports: List[AuditReport]):
    # Sort by overall score descending
    sorted_reports = sorted(reports, key=lambda r: r.overall_score, reverse=True)
    compatible_count = sum(1 for r in reports if r.is_compatible)
    incompatible_count = len(reports) - compatible_count

    console.print("\n")
    console.print(Panel(
        f"[bold white]Total Websites Audited:[/] [cyan]{len(reports)}[/]  |  "
        f"[bold white]Compatible with iPad Air 1:[/] [bold green]{compatible_count}[/bold green]  |  "
        f"[bold white]Incompatible / Blocked:[/] [bold red]{incompatible_count}[/bold red]",
        title="[bold]Batch Compatibility Audit Results[/bold]",
        border_style="cyan"
    ))

    table = Table(show_header=True, header_style="bold cyan")
    table.add_column("#", style="dim", width=3, justify="right")
    table.add_column("Source / Domain", style="bold white", width=22)
    table.add_column("Score", width=6, justify="right")
    table.add_column("Verdict", width=15)
    table.add_column("Language", width=14)
    table.add_column("Network", width=16)
    table.add_column("CMS Detected", width=18)
    table.add_column("Stream / Codec", width=22)

    for idx, r in enumerate(sorted_reports, 1):
        if r.is_compatible:
            verdict_str = "[bold green]COMPATIBLE[/bold green]"
            score_str = f"[bold green]{r.overall_score}[/bold green]"
        elif r.overall_score >= 40:
            verdict_str = "[yellow]NEEDS TWEAKS[/yellow]"
            score_str = f"[yellow]{r.overall_score}[/yellow]"
        else:
            verdict_str = "[bold red]REJECTED[/bold red]"
            score_str = f"[bold red]{r.overall_score}[/bold red]"

        # Language status
        if r.language_audit:
            if r.language_audit.is_acceptable:
                lang_str = "[bold green]Eng Sub/Dub[/bold green]"
            elif "sub indo" in r.language_audit.status.lower() or "indonesian" in r.language_audit.status.lower():
                lang_str = "[bold red]Sub Indo[/bold red]"
            else:
                lang_str = "[bold red]Non-English[/bold red]"
        else:
            lang_str = "[dim]Unknown[/dim]"

        # Network status
        if not r.network_hop.passed:
            net_str = "[red]BLOCKED (403/WAF)[/]"
        elif r.use_proxy:
            net_str = "[yellow]Proxy Needed[/]"
        else:
            net_str = "[green]Direct (200 OK)[/]"

        # Stream
        if r.stream_audit:
            stream_str = f"{r.stream_audit.server_name} ({r.stream_audit.codec[:12]})"
            if not r.stream_audit.is_hw_accelerated:
                stream_str = f"[bold red]{r.stream_audit.codec[:12]}[/bold red]"
            else:
                stream_str = f"[green]{r.stream_audit.codec[:12]}[/green]"
        elif r.servers_hop.passed:
            stream_str = "[yellow]Direct Links[/]"
        elif "Shortener" in (r.servers_hop.error or ""):
            stream_str = "[bold red]Ad Shorteners[/bold red]"
        else:
            stream_str = "[dim]None[/dim]"

        table.add_row(
            str(idx),
            r.url.replace("https://", "").replace("http://", ""),
            score_str,
            verdict_str,
            lang_str,
            net_str,
            r.cms_detected[:18],
            stream_str
        )

    console.print(table)

def display_sources_table(sources: list):
    table = Table(title="Active Matnami Anime Sources (Sources/sources.json)", show_header=True, header_style="bold red")
    table.add_column("ID", style="cyan", width=14)
    table.add_column("Name", style="bold white", width=18)
    table.add_column("Base URL", style="dim")
    table.add_column("Proxy Required?", justify="center", width=16)

    for s in sources:
        proxy_str = "[yellow]YES[/]" if s.get("useProxy", False) else "[green]NO (Direct)[/]"
        table.add_row(s.get("id", ""), s.get("name", ""), s.get("baseURL", ""), proxy_str)

    console.print(table)

