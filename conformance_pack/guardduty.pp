locals {
  conformance_pack_guardduty_common_tags = merge(local.aws_compliance_common_tags, {
    service = "AWS/GuardDuty"
  })
}

control "guardduty_enabled" {
  title       = "GuardDuty should be enabled"
  description = "AWS GuardDuty can help to monitor and detect potential cybersecurity events by using threat intelligence feeds."
  query       = query.guardduty_enabled
  severity    = "high"
  tags = merge(local.conformance_pack_guardduty_common_tags, {
    cis_controls_v8_ig1                    = "true"
    cisa_cyber_essentials                  = "true"
    fedramp_low_rev_4                      = "true"
    fedramp_moderate_rev_4                 = "true"
    ffiec                                  = "true"
    gxp_21_cfr_part_11                     = "true"
    gxp_eu_annex_11                        = "true"
    hipaa_final_omnibus_security_rule_2013 = "true"
    hipaa_security_rule_2003               = "true"
    nist_800_171_rev_2                     = "true"
    nist_800_53_rev_4                      = "true"
    nist_800_53_rev_5                      = "true"
    nist_csf                               = "true"
    nydfs_23                               = "true"
    pci_dss_v321                           = "true"
    pci_dss_v40                            = "true"
    rbi_itf_nbfc                           = "true"
    soc_2                                  = "true"
  })
}

control "guardduty_finding_archived" {
  title       = "GuardDuty findings should be archived"
  description = "AWS GuardDuty helps you understand the impact of an incident by classifying findings by severity: low, medium, and high."
  query       = query.guardduty_finding_archived
  severity    = "high"
  tags = merge(local.conformance_pack_guardduty_common_tags, {
    fedramp_low_rev_4                      = "true"
    fedramp_moderate_rev_4                 = "true"
    ffiec                                  = "true"
    gxp_eu_annex_11                        = "true"
    hipaa_final_omnibus_security_rule_2013 = "true"
    hipaa_security_rule_2003               = "true"
    nist_800_171_rev_2                     = "true"
    nist_800_53_rev_4                      = "true"
    nist_800_53_rev_5                      = "true"
    nist_csf                               = "true"
    pci_dss_v321                           = "true"
    rbi_cyber_security                     = "true"
    rbi_itf_nbfc                           = "true"
    soc_2                                  = "true"
  })
}

control "guardduty_no_high_severity_findings" {
  title       = "GuardDuty Detector should not have high severity findings"
  description = "GuardDuty generates a finding whenever it detects unexpected and potentially malicious activity in your AWS environment. If critical findings are not addressed threats can spread in the environment. This rule is non-compliant if there are high severity findings."
  query       = query.guardduty_no_high_severity_findings
  severity    = "high"
  tags = local.conformance_pack_guardduty_common_tags
}

control "guardduty_centrally_configured" {
  title       = "GuardDuty Detector should be centrally configured"
  description = "Ensure that GuardDuty is centrally configured, if GuardDuty is not under central management, it becomes impossible to centrally manage GuardDuty findings, settings, and member accounts."
  query       = query.guardduty_centrally_configured
  severity    = "high"
  tags = local.conformance_pack_guardduty_common_tags
}

query "guardduty_enabled" {
  sql = <<-EOQ
    select
      'arn:' || r.partition || '::' || r.region || ':' || r.account_id as resource,
      case
        when r.steampipe_available = false then 'skip'
        when r.region = any(array['af-south-1', 'ap-northeast-3', 'ap-southeast-3', 'eu-south-1', 'cn-north-1', 'cn-northwest-1', 'me-south-1', 'us-gov-east-1']) then 'skip'
        when r.opt_in_status = 'not-opted-in' then 'skip'
        when d.status = 'ENABLED' and d.master_account ->> 'AccountId' is null then 'ok'
        when d.status = 'ENABLED' and d.master_account ->> 'AccountId' is not null then 'info'
        else 'alarm'
      end as status,
      case
        when r.steampipe_available = false then r.region || ' is not available in the current connection configuration.'
        when r.region = any(array['af-south-1', 'ap-northeast-3', 'ap-southeast-3', 'eu-south-1', 'cn-north-1', 'cn-northwest-1', 'me-south-1', 'us-gov-east-1']) then r.region || ' region not supported.'
        when r.opt_in_status = 'not-opted-in' then r.region || ' region is disabled.'
        when d.status is null then 'No GuardDuty detector found in ' || r.region || '.'
        when d.status = 'ENABLED' and d.master_account ->> 'AccountId' is null then r.region || ' detector ' || d.title || ' enabled.'
        when d.status = 'ENABLED' and d.master_account ->> 'AccountId' is not null then r.region || ' detector ' || d.title || ' is managed by account ' || (d.master_account ->> 'AccountId') ||  ' via delegated admin.'
        else r.region || ' detector ' || d.title || ' disabled.'
      end as reason
      ${replace(local.common_dimensions_qualifier_sql, "__QUALIFIER__", "r.")}
    from
      aws_region as r
      left join aws_guardduty_detector d on r.account_id = d.account_id and r.name = d.region;
  EOQ
}


query "guardduty_no_high_severity_findings" {
  sql = <<-EOQ
    with detectors as (
      select
        d.detector_id,
        d.arn,
        d.title,
        d.region,
        d.account_id,
        d.tags,
        d.status
      from
        aws_guardduty_detector d
        join aws_region r on d.account_id = r.account_id and d.region = r.name
      where
        r.steampipe_available = true
    ),
    finding_count as (
      select
        f.detector_id,
        count(*) as count
      from
        aws_guardduty_finding as f
      group by
        f.detector_id
    )
    select
      d.arn as resource,
      case
        when d.status <> 'ENABLED' then 'skip'
        when fc.count = 0 or fc.count is null then 'ok'
        else 'alarm'
      end as status,
      case
        when d.status <> 'ENABLED' then d.detector_id || ' is disabled.'
        when fc.count = 0 or fc.count is null then d.detector_id || ' is enabled and does not have high severity findings.'
        else d.detector_id || ' is enabled and has ' || fc.count || ' high severity findings.'
      end as reason
      ${replace(local.tag_dimensions_qualifier_sql, "__QUALIFIER__", "d.")}
      ${replace(local.common_dimensions_qualifier_sql, "__QUALIFIER__", "d.")}
    from
      detectors as d
      left join finding_count as fc on fc.detector_id = d.detector_id;
  EOQ
}


query "guardduty_finding_archived" {
  sql = <<-EOQ
    select
      arn as resource,
      case
        when service ->> 'Archived' = 'false' then 'alarm'
        else 'ok'
      end as status,
      case
        when service ->> 'Archived' = 'false' then title || ' not archived.'
        else title || ' archived.'
      end as reason
      ${local.common_dimensions_sql}
    from
      aws_guardduty_finding;
  EOQ
}

query "guardduty_centrally_configured" {
  sql = <<-EOQ
    select
      'arn:' || r.partition || '::' || r.region || ':' || r.account_id as resource,
      case
        -- Skip if region is is not available in the current connection configuration (i.e., not available to Steampipe)
        when r.steampipe_available = false then 'skip'
        when r.region = any(array['af-south-1', 'ap-northeast-3', 'ap-southeast-3', 'eu-south-1', 'cn-north-1', 'cn-northwest-1', 'me-south-1', 'us-gov-east-1']) then 'skip'
        when r.opt_in_status = 'not-opted-in' then 'skip'
        when d.status is null then 'info'
        when d.status = 'DISABLED' then 'alarm'
        when d.status = 'ENABLED' and d.master_account ->> 'AccountId' is not null then 'ok'
        else 'alarm'
      end as status,
      case
        when r.steampipe_available = false then r.region || ' is not available in the current connection configuration.'
        when r.region = any(array['af-south-1', 'ap-northeast-3', 'ap-southeast-3', 'eu-south-1', 'cn-north-1', 'cn-northwest-1', 'me-south-1', 'us-gov-east-1']) then r.region || ' region not supported.'
        when r.opt_in_status = 'not-opted-in' then r.region || ' region is disabled.'
        when d.status is null then 'No GuardDuty detector found in ' || r.region || '.'
        when d.status = 'DISABLED' then r.region || ' detector ' || d.title || ' disabled.'
        when d.status = 'ENABLED' and d.master_account ->> 'AccountId' is not null then r.region || ' detector ' || d.title || ' centrally configured.'
        else r.region || ' detector ' || d.title || ' not centrally configured.'
      end as reason
    ${replace(local.common_dimensions_qualifier_sql, "__QUALIFIER__", "r.")}
    from
      aws_region as r
      left join aws_guardduty_detector d on r.account_id = d.account_id and r.name = d.region;
  EOQ
}


