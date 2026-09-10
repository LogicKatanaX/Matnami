import json
from typing import List
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.syntax import Syntax
from rich.text import Text

from .models import AuditReport

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

    # Recommendations
    if report.recommendations:
        console.print("\n[bold yellow]Auditor Recommendations:[/bold yellow]")
        for rec in report.recommendations:
            console.print(f"  [yellow]•[/yellow] {rec}")

    # Suggested sources.json configuration
    if report.suggested_config:
        console.print("\n[bold cyan]Generated sources.json Configuration:[/bold cyan]")
        formatted_json = json.dumps(report.suggested_config, indent=2)
        syntax = Syntax(formatted_json, "json", theme="monokai", line_numbers=False)
        console.print(syntax)

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
    table.add_column("#", style="dim", width=4, justify="right")
    table.add_column("Source / Domain", style="bold white", width=24)
    table.add_column("Score", width=8, justify="right")
    table.add_column("Verdict", width=18)
    table.add_column("Network / Bot Wall", width=18)
    table.add_column("CMS Detected", width=20)
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

        # Network status
        if not r.network_hop.passed:
            net_str = "[red]BLOCKED (403/Fail)[/]"
        elif r.use_proxy:
            net_str = "[yellow]Proxy Needed[/]"
        else:
            net_str = "[green]Direct (200 OK)[/]"

        # Stream
        if r.stream_audit:
            stream_str = f"{r.stream_audit.server_name} ({r.stream_audit.codec[:12]})"
        elif r.servers_hop.passed:
            stream_str = "[yellow]Servers Found[/]"
        else:
            stream_str = "[dim]None[/dim]"

        table.add_row(
            str(idx),
            r.url.replace("https://", "").replace("http://", ""),
            score_str,
            verdict_str,
            net_str,
            r.cms_detected[:20],
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

