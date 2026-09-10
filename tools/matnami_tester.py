#!/usr/bin/env python3
"""
Matnami Source Tester & Compatibility Suite
===========================================
Audits anime streaming & download websites for compatibility with:
  • iPad Air 1 (2013, Apple A7, 1GB RAM)
  • iOS 12.0 - 12.5.7/12.5.8
  • Hardware H.264 (AVC) VDA / Apple HLS
  • Download-First direct socket downloads

Usage:
  python tools/matnami_tester.py              (Interactive Menu)
  python tools/matnami_tester.py list         (List active sources)
  python tools/matnami_tester.py test <url>   (Strict suitability audit)
  python tools/matnami_tester.py test-all     (Audit all sources in sources.json)
  python tools/matnami_tester.py batch "<dump>" (Batch audit markdown or URL dump)
  python tools/matnami_tester.py batch-file <file> (Batch audit URLs from a text file)
  python tools/matnami_tester.py add <url>    (Audit & save to Sources/sources.json)
  python tools/matnami_tester.py remove <id>  (Remove source from sources.json)
"""

import sys
import os
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List

# Ensure UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from matnami.validator import WebsiteAuditor
from matnami.source_manager import SourceManager
from matnami.ui import console, print_banner, display_audit_report, display_sources_table
from matnami.url_extractor import extract_urls_from_text
from matnami.models import AuditReport
from matnami.ui import (
    console, print_banner, display_audit_report,
    display_sources_table, display_batch_summary_table
)

def cmd_list(sm: SourceManager):
    sources = sm.list_sources()
    display_sources_table(sources)

def cmd_test(auditor: WebsiteAuditor, sm: SourceManager, url: str):
    # Check if url belongs to an existing configured source
    sources = sm.list_sources()
    existing = next((s for s in sources if s.get("baseURL", "").rstrip("/") in url.rstrip("/")), None)

    with console.status(f"[bold cyan]Running 4-Hop compatibility audit on {url}...[/bold cyan]"):
        report = auditor.audit_url(url, existing_config=existing)

    console.print(f"[bold cyan]Running 4-Hop compatibility audit on {url}...[/bold cyan]")
    report = auditor.audit_url(url, existing_config=existing)
    display_audit_report(report)
    return report

def cmd_test_all(auditor: WebsiteAuditor, sm: SourceManager):
    sources = sm.list_sources()
    if not sources:
        console.print("[yellow]No sources found in Sources/sources.json[/yellow]")
        return

    console.print(f"[bold cyan]Auditing all {len(sources)} sources in Sources/sources.json...[/bold cyan]\n")
    for s in sources:
        url = s.get("baseURL")
        if url:
            with console.status(f"[bold cyan]Auditing {s.get('name')} ({url})...[/bold cyan]"):
                report = auditor.audit_url(url, existing_config=s)
            console.print(f"[bold cyan]Auditing {s.get('name')} ({url})...[/bold cyan]")
            report = auditor.audit_url(url, existing_config=s)
            display_audit_report(report)
            console.print("\n" + "─" * 60 + "\n")
            console.print("\n" + "-" * 60 + "\n")

def cmd_batch(auditor: WebsiteAuditor, sm: SourceManager, raw_text: str, auto_save: bool = False):
    urls = extract_urls_from_text(raw_text)
    if not urls:
        console.print("[bold red]No valid URLs or domains discovered in the provided dump.[/bold red]")
        return []

    console.print(f"\n[bold cyan]Discovered {len(urls)} distinct website(s) to audit:[/bold cyan]")
    for idx, u in enumerate(urls, 1):
        console.print(f"  [dim]{idx}.[/dim] {u}")

    console.print(f"\n[bold yellow]Launching concurrent 4-hop audit pipeline (Workers: 5)...[/bold yellow]\n")

    reports: List[AuditReport] = []
    sources = sm.list_sources()

    def audit_worker(target_url: str) -> AuditReport:
        existing = next((s for s in sources if s.get("baseURL", "").rstrip("/") in target_url.rstrip("/")), None)
        worker_auditor = WebsiteAuditor()
        return worker_auditor.audit_url(target_url, existing_config=existing)

    with ThreadPoolExecutor(max_workers=5) as executor:
        future_to_url = {executor.submit(audit_worker, u): u for u in urls}
        completed_count = 0
        for future in as_completed(future_to_url):
            u = future_to_url[future]
            completed_count += 1
            try:
                rep = future.result()
                reports.append(rep)
                symbol = "[green][PASS][/green]" if rep.is_compatible else "[red][REJECT][/red]"
                console.print(f"[{completed_count:02d}/{len(urls):02d}] {symbol} [bold]{rep.source_name}[/] ({rep.url}) - Score: {rep.overall_score}/100")
            except Exception as e:
                console.print(f"[{completed_count:02d}/{len(urls):02d}] [red][ERROR][/red] {u} -> {e}")

    # Display full sorted summary table
    display_batch_summary_table(reports)

    compatible = [r for r in reports if r.is_compatible and r.suggested_config]
    if compatible:
        if auto_save:
            save_compatible = True
        else:
            try:
                choice = console.input(f"\n[bold yellow]Found {len(compatible)} compatible source(s). Save to Sources/sources.json? [y/N]: [/bold yellow]").strip().lower()
                save_compatible = choice in ("y", "yes")
            except Exception:
                save_compatible = False

        if save_compatible:
            for c in compatible:
                sm.save_source(c.suggested_config)
                console.print(f"[bold green]Added:[/] {c.source_name} to Sources/sources.json")

    return reports

def cmd_batch_file(auditor: WebsiteAuditor, sm: SourceManager, file_path: str):
    if not os.path.exists(file_path):
        console.print(f"[bold red]File not found: {file_path}[/bold red]")
        return
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    cmd_batch(auditor, sm, content)

def cmd_add(auditor: WebsiteAuditor, sm: SourceManager, url: str):
    report = cmd_test(auditor, sm, url)
    if not report.is_compatible or not report.suggested_config:
        console.print("\n[bold red]Strict Rejection:[/] Website does not meet our reliability rubric for iOS 12. Not added.")
        return

    console.print(f"\n[bold cyan]Adding '{report.suggested_config['name']}' to Sources/sources.json...[/bold cyan]")
    ok = sm.save_source(report.suggested_config)
    if ok:
        console.print(f"[bold green]SUCCESS:[/] Added {report.suggested_config['name']} to Sources/sources.json")
    else:
        console.print("[bold red]ERROR:[/] Failed to write to Sources/sources.json")

def cmd_remove(sm: SourceManager, source_id: str):
    console.print(f"[bold yellow]Removing '{source_id}' from Sources/sources.json...[/bold yellow]")
    ok = sm.remove_source(source_id)
    if ok:
        console.print(f"[bold green]SUCCESS:[/] Removed {source_id}")
    else:
        console.print(f"[bold red]ERROR:[/] Source '{source_id}' not found.")

def interactive_menu():
    print_banner()
    sm = SourceManager()
    auditor = WebsiteAuditor()

    while True:
        console.print("\n[bold cyan]Dashboard Actions:[/bold cyan]")
        console.print("  [1] List Active Anime Sources (Sources/sources.json)")
        console.print("  [2] Audit a Website (Test 4-Hop & iPad Air 1 Compatibility)")
        console.print("  [3] Audit ALL Active Anime Sources")
        console.print("  [4] Add New Anime Website (Audit + Auto-Save to sources.json)")
        console.print("  [5] Remove an Anime Source")
        console.print("  [2] Audit a Single Website (Test 4-Hop & iPad Air 1 Compatibility)")
        console.print("  [3] Audit ALL Active Anime Sources in sources.json")
        console.print("  [4] Batch Audit / Dump Website List (Paste markdown links or URL dump)")
        console.print("  [5] Batch Audit from Text File")
        console.print("  [6] Add New Anime Website (Audit + Auto-Save to sources.json)")
        console.print("  [7] Remove an Anime Source")
        console.print("  [0] Exit")

        choice = console.input("\n[bold yellow]Select an option [0-5]: [/bold yellow]").strip()
        choice = console.input("\n[bold yellow]Select an option [0-7]: [/bold yellow]").strip()

        if choice == "1":
            cmd_list(sm)
        elif choice == "2":
            url = console.input("[bold white]Enter Anime Website URL to Audit: [/bold white]").strip()
            if url:
                cmd_test(auditor, sm, url)
        elif choice == "3":
            cmd_test_all(auditor, sm)
        elif choice == "4":
            console.print("\n[bold green]Paste your website dump below (Markdown links, URLs, or domains).[/bold green]")
            console.print("[dim]Press Enter on an empty line when finished:[/dim]\n")
            lines = []
            while True:
                try:
                    line = input()
                    if not line:
                        break
                    lines.append(line)
                except EOFError:
                    break
            raw_dump = "\n".join(lines)
            if raw_dump.strip():
                cmd_batch(auditor, sm, raw_dump)
        elif choice == "5":
            f_path = console.input("[bold white]Enter text file path: [/bold white]").strip().strip('"')
            if f_path:
                cmd_batch_file(auditor, sm, f_path)
        elif choice == "6":
            url = console.input("[bold white]Enter New Website URL to Audit & Add: [/bold white]").strip()
            if url:
                cmd_add(auditor, sm, url)
        elif choice == "7":
            s_id = console.input("[bold white]Enter Source ID to remove: [/bold white]").strip()
            if s_id:
                cmd_remove(sm, s_id)
        elif choice == "0":
            console.print("[bold green]Goodbye![/bold green]")
            break
        else:
            console.print("[red]Invalid selection.[/red]")

def main():
    parser = argparse.ArgumentParser(description="Matnami Source Tester & Compatibility Auditor")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("list", help="List active anime sources")
    subparsers.add_parser("test-all", help="Audit all configured sources")

    test_parser = subparsers.add_parser("test", help="Audit a specific website URL")
    test_parser.add_argument("url", help="Target website URL")

    batch_parser = subparsers.add_parser("batch", help="Batch audit a dump of URLs or markdown links")
    batch_parser.add_argument("dump", help="Raw text containing links/domains")

    batch_file_parser = subparsers.add_parser("batch-file", help="Batch audit URLs from a text file")
    batch_file_parser.add_argument("file", help="Path to text file containing URLs")

    add_parser = subparsers.add_parser("add", help="Audit and add a website to sources.json")
    add_parser.add_argument("url", help="Target website URL")

    remove_parser = subparsers.add_parser("remove", help="Remove a source from sources.json")
    remove_parser.add_argument("id", help="Source ID to remove")

    args = parser.parse_args()

    sm = SourceManager()
    auditor = WebsiteAuditor()

    if args.command == "list":
        cmd_list(sm)
    elif args.command == "test":
        cmd_test(auditor, sm, args.url)
    elif args.command == "test-all":
        cmd_test_all(auditor, sm)
    elif args.command == "batch":
        cmd_batch(auditor, sm, args.dump)
    elif args.command == "batch-file":
        cmd_batch_file(auditor, sm, args.file)
    elif args.command == "add":
        cmd_add(auditor, sm, args.url)
    elif args.command == "remove":
        cmd_remove(sm, args.id)
    else:
        interactive_menu()

if __name__ == "__main__":
    main()

