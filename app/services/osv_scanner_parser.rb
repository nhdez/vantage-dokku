class OsvScannerParser
  def initialize(raw_output)
    @raw_output = raw_output
    @lines = raw_output.split("\n")
  end

  def parse
    Rails.logger.info "[OsvScannerParser] Parsing output (#{@raw_output.length} characters)"
    Rails.logger.debug "[OsvScannerParser] Raw output: #{@raw_output}"

    result = {
      success: !@raw_output.include?('Error'),
      total_packages: extract_total_packages,
      vulnerabilities_found: extract_vulnerability_count,
      severity_counts: extract_severity_counts,
      vulnerabilities: extract_vulnerabilities,
      summary: extract_summary
    }

    Rails.logger.info "[OsvScannerParser] Parsed result: #{result.except(:vulnerabilities).inspect}"
    Rails.logger.info "[OsvScannerParser] Found #{result[:vulnerabilities].count} vulnerabilities"

    result
  end

  private

  def extract_total_packages
    # Look for line like: "Scanned /path/Gemfile.lock file and found 169 packages"
    package_lines = @lines.select { |line| line.include?('found') && line.include?('packages') }
    package_lines.sum do |line|
      match = line.match(/found (\d+) packages/)
      match ? match[1].to_i : 0
    end
  end

  def extract_vulnerability_count
    # Look for line like: "Total 4 packages affected by 9 known vulnerabilities"
    summary_line = @lines.find { |line| line.include?('packages affected by') && line.include?('known vulnerabilities') }
    return 0 unless summary_line

    match = summary_line.match(/by (\d+) known vulnerabilities/)
    match ? match[1].to_i : 0
  end

  def extract_severity_counts
    # Look for line like: "(0 Critical, 4 High, 3 Medium, 2 Low, 0 Unknown)"
    counts = { critical: 0, high: 0, medium: 0, low: 0, unknown: 0 }

    summary_line = @lines.find { |line| line.include?('Critical') && line.include?('High') }
    return counts unless summary_line

    counts[:critical] = extract_count(summary_line, 'Critical')
    counts[:high] = extract_count(summary_line, 'High')
    counts[:medium] = extract_count(summary_line, 'Medium')
    counts[:low] = extract_count(summary_line, 'Low')
    counts[:unknown] = extract_count(summary_line, 'Unknown')

    counts
  end

  def extract_count(line, severity)
    match = line.match(/(\d+) #{severity}/)
    match ? match[1].to_i : 0
  end

  def extract_summary
    # Everything before the table (if present) or the whole output if no vulnerabilities
    if @raw_output.include?('No issues found')
      'No vulnerabilities found'
    elsif @raw_output.include?('known vulnerabilities')
      summary_line = @lines.find { |line| line.include?('packages affected by') && line.include?('known vulnerabilities') }
      summary_line || 'Scan completed'
    else
      'Scan completed'
    end
  end

  def extract_vulnerabilities
    vulns = []

    # Find the table section
    table_start = @lines.index { |line| line.include?('OSV URL') && line.include?('CVSS') }
    return vulns unless table_start

    # Skip header and separator lines
    data_start = table_start + 2

    @lines[data_start..-1].each do |line|
      # Stop at table end
      break if line.start_with?('╰') || line.strip.empty?

      # Skip separator lines
      next if line.start_with?('├')

      # Parse vulnerability data
      vuln = parse_vulnerability_line(line)
      vulns << vuln if vuln
    end

    vulns
  end

  def parse_vulnerability_line(line)
    # Split by │ and clean up
    parts = line.split('│').map(&:strip).reject(&:empty?)
    return nil if parts.length < 7

    # Determine severity from CVSS score
    cvss = parts[1].to_f
    severity = severity_from_cvss(cvss)

    {
      osv_url: parts[0],
      osv_id: extract_osv_id(parts[0]),
      cvss_score: cvss,
      ecosystem: parts[2],
      package_name: parts[3],
      current_version: parts[4],
      fixed_version: parts[5],
      source_file: parts[6],
      severity: severity
    }
  rescue => e
    Rails.logger.error "Failed to parse vulnerability line: #{line}"
    Rails.logger.error "Error: #{e.message}"
    nil
  end

  def extract_osv_id(url)
    # Extract ID from URL like "https://osv.dev/GHSA-9hjg-9r4m-mvj7"
    match = url.match(%r{osv\.dev/([A-Z0-9-]+)})
    match ? match[1] : url
  end

  def severity_from_cvss(score)
    return 'Unknown' if score.zero?
    return 'Critical' if score >= 9.0
    return 'High' if score >= 7.0
    return 'Medium' if score >= 4.0
    'Low'
  end
end
