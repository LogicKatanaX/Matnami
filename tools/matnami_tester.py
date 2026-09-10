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
  python tools/matnami_tester.py add <url>    (Audit & save to Sources/sources.json)
  python tools/matnami_tester.py remove <id>  (Remove source from sources.json)
"""

import sys
import argparse
from matnami.validator import WebsiteAuditor
from matnami.source_manager import SourceManager
from matnami.ui import console, print_banner, display_audit_report, display_sources_table

def cmd_list(sm: SourceManager):
    sources = sm.list_sources()
    display_sources_table(sources)

def cmd_test(auditor: WebsiteAuditor, sm: SourceManager, url: str):
    # Check if url belongs to an existing configured source
    sources = sm.list_sources()
    existing = next((s for s in sources if s.get("baseURL", "").rstrip("/") in url.rstrip("/")), None)

    with console.status(f"[bold cyan]Running 4-Hop compatibility audit on {url}...[/bold cyan]"):
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
            display_audit_report(report)
            console.print("\n" + "─" * 60 + "\n")

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
        console.print("  [0] Exit")

        choice = console.input("\n[bold yellow]Select an option [0-5]: [/bold yellow]").strip()

        if choice == "1":
            cmd_list(sm)
        elif choice == "2":
            url = console.input("[bold white]Enter Anime Website URL to Audit: [/bold white]").strip()
            if url:
                cmd_test(auditor, sm, url)
        elif choice == "3":
            cmd_test_all(auditor, sm)
        elif choice == "4":
            url = console.input("[bold white]Enter New Website URL to Audit & Add: [/bold white]").strip()
            if url:
                cmd_add(auditor, sm, url)
        elif choice == "5":
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
    elif args.command == "add":
        cmd_add(auditor, sm, args.url)
    elif args.command == "remove":
        cmd_remove(sm, args.id)
    else:
        interactive_menu()

if __name__ == "__main__":
    main()
