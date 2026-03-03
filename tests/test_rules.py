from unittest.mock import patch, MagicMock
from cost_guardian.rules.ebs_unattached import EBSUnattachedRule
from cost_guardian.rules.eip_unassociated import EIPUnassociatedRule
from cost_guardian.models import Finding

## EBS Tests--
@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_returns_findings_for_available_volumes(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {
        "Volumes": [
            {"VolumeId": "vol-123", "Size": 100, "VolumeType": "gp3"}
        ]
    }
    rule = EBSUnattachedRule("us-east-1")
    findings = rule.run()
    assert len(findings) == 1
    assert findings[0].resource_id == "vol-123"

@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_calculates_waste_correctly(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {
        "Volumes": [
            {"VolumeId": "vol-456", "Size": 100, "VolumeType": "gp3"}
        ]
    }
    rule = EBSUnattachedRule("us-east-1")
    findings = rule.run()
    assert findings[0].estimated_monthly_waste == 8.00

@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_returns_empty_when_no_volumes(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {"Volumes": []}
    rule = EBSUnattachedRule("us-east-1")
    findings = rule.run()
    assert findings == []

@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_finding_has_correct_region(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {
        "Volumes": [
            {"VolumeId": "vol-789", "Size": 50, "VolumeType": "gp2"}
        ]
    }
    rule = EBSUnattachedRule("eu-west-1")
    findings = rule.run()
    assert findings[0].region == "eu-west-1"


@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_finding_contains_size_in_details(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {
        "Volumes": [
            {"VolumeId": "vol-999", "Size": 200, "VolumeType": "gp3"}
        ]
    }
    rule = EBSUnattachedRule("us-east-1")
    findings = rule.run()
    assert findings[0].details["size_gb"] == 200


@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_rule_name_is_correct(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {
        "Volumes": [
            {"VolumeId": "vol-111", "Size": 50, "VolumeType": "gp3"}
        ]
    }
    rule = EBSUnattachedRule("us-east-1")
    findings = rule.run()
    assert findings[0].rule == "UNATTACHED_EBS"


@patch("cost_guardian.rules.ebs_unattached.boto3.client")
def test_ebs_multiple_volumes_returns_multiple_findings(mock_boto):
    mock_ec2 = MagicMock()
    mock_boto.return_value = mock_ec2
    mock_ec2.describe_volumes.return_value = {
        "Volumes": [
            {"VolumeId": "vol-aaa", "Size": 50,  "VolumeType": "gp3"},
            {"VolumeId": "vol-bbb", "Size": 100, "VolumeType": "gp2"},
        ]
    }
    rule = EBSUnattachedRule("us-east-1")
    findings = rule.run()
    assert len(findings) == 2