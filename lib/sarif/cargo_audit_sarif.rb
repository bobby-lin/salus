module Sarif
  class CargoAuditSarif < BaseSarif
    include Salus::SalusBugsnag

    CARGO_AUDIT_URI = 'https://github.com/RustSec/cargo-audit/'.freeze

    def initialize(scan_report)
      super(scan_report)
      @uri = CARGO_AUDIT_URI
      @logs = parse_scan_report!
    end

    def parse_scan_report!
      logs = @scan_report.log('')
      return [] if logs.strip.empty?

      x = JSON.parse(logs)
      vulnerabilities = x['vulnerabilities']['list'] || []
      unmaintained = x['warnings']['unmaintained'] || []
      yanked = x['warnings']['yanked'] || []
      vulnerabilities.concat(unmaintained, yanked)
    rescue JSON::ParserError => e
      bugsnag_notify(e.message)
      []
    end

    def parse_yanked(issue)
      package = issue['package']
      return nil if issue.include?(package['name'] + '/ Yanked')

      @issues.add(package['name'] + '/ Yanked')
      {
        id: package['name'] + '/ Yanked',
        name: package['name'] + '/ Yanked',
        level: "low",
        details: "Package:#{package['name']}\nVersion:#{package['version']}\nSource:"\
        "#{package['source']}\nKind: yanked",
        uri: 'Cargo.lock',
        help_url: package['source']
      }
    end

    def parse_issue(issue)
      return parse_yanked(issue) if issue['kind'] == 'yanked'
      return nil if @issues.include?(issue.dig('advisory', 'id'))

      @issues.add(issue.dig('advisory', 'id'))
      advisory = issue['advisory'] || {}
      parsed_issue = {
        id: advisory['id'],
        name: advisory['title'],
        level: "HIGH",
        details: "Package: #{advisory['package']}\nTitle: #{advisory['title']}\nDescription: "\
        "#{advisory['description']}\nPatched: #{issue.dig('versions', 'patched')}"\
        "\nUnaffected: #{issue.dig('versions', 'unaffected')}\nCVSS: #{advisory['cvss']}",
        uri: 'Cargo.lock',
        help_url: issue['advisory']['url']
      }
      if issue['kind'] == 'unmaintained'
        parsed_issue[:level] = 'LOW'
        parsed_issue[:details] << "\nKind: unmaintained"
      end
      parsed_issue
    end
  end
end
