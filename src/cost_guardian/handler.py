import json
import os
import boto3
import urllib.request
import datetime
from collections import defaultdict

from cost_guardian.engine import CostEngine

ssm = boto3.client("ssm")
s3 = boto3.client("s3")
cloudwatch = boto3.client("cloudwatch")

def get_slack_webhook():
    param_name = os.environ["SLACK_PARAM"]
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    return response["Parameter"]["Value"]


def send_slack_message(webhook_url, message):
    payload = {"text": message}
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
    )

    with urllib.request.urlopen(req) as response:
        return response.read()


def save_report_to_s3(report, timestamp):
    bucket = os.environ["REPORT_BUCKET"]

    dt = datetime.datetime.utcnow()
    key = (
        f"reports/{dt.year}/"
        f"{dt.month:02d}/"
        f"{dt.day:02d}/"
        f"report-{timestamp}.json"
    )

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(report, indent=2),
        ContentType="application/json",
    )

    return key

def publish_metrics(report):
    total_waste = report.get("total_estimated_monthly_waste", 0)
    findings = report.get("findings", [])
 
    cloudwatch.put_metric_data(
        Namespace="CostGuardian",
        MetricData=[
            {
                "MetricName": "TotalEstimatedMonthlyWaste",
                "Value": total_waste,
                "Unit": "None"
            },
            {
                "MetricName": "TotalFindings",
                "Value": len(report["findings"]),
                "Unit": "Count"
            }
        ]
    )

def format_summary(report):
    findings = report["findings"]
    total_waste = report["total_estimated_monthly_waste"]
    regions = report["regions_scanned"]

    findings_count = len(findings)

    rule_counts = defaultdict(int)
    for f in findings:
        rule_counts[f["rule"]] += 1

    top_offenders = sorted(
        findings,
        key=lambda x: x["estimated_monthly_waste"],
        reverse=True
    )[:3]

    lines = []
    lines.append("*Cost Guardian Report*")
    lines.append(f"Regions scanned: {len(regions)}")
    lines.append(f"Total findings: {findings_count}")
    lines.append(f"Estimated monthly waste: ${total_waste}")
    lines.append("")

    if findings_count == 0:
        lines.append("Account is clean. No waste detected.")
    else:
        lines.append("*Findings by Rule:*")
        for rule, count in rule_counts.items():
            lines.append(f"- {rule}: {count}")

        lines.append("")
        lines.append("*Top Offenders:*")
        for offender in top_offenders:
            lines.append(
                f"- {offender['rule']} | "
                f"{offender['resource_id']} | "
                f"${offender['estimated_monthly_waste']}"
            )

    return "\n".join(lines)


def lambda_handler(event, context):
    timestamp = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%S")

    engine = CostEngine()
    report = engine.run()

    publish_metrics(report)

    s3_key = save_report_to_s3(report, timestamp)

    summary_message = format_summary(report)
    summary_message += f"\n\nFull report saved to: s3://{os.environ['REPORT_BUCKET']}/{s3_key}"

    webhook = get_slack_webhook()
    send_slack_message(webhook, summary_message)

    print(json.dumps({
        "timestamp": timestamp,
        "s3_key": s3_key,
        "report": report
    }))

    return {
        "status": "sent",
        "timestamp": timestamp,
        "s3_key": s3_key
    }

