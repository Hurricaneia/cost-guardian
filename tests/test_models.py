from cost_guardian.models import Finding

def test_finding_has_correct_field():
    finding = Finding(
        rule="TestRule",
        resource_id="vol-12345",
        region ="us-east-1",
        estimated_monthly_waste=8.00,
        details={"size_gb": 100}
    )
    assert finding.rule == "TestRule"
    assert finding.resource_id == "vol-12345"
    assert finding.region == "us-east-1"
    assert finding.estimated_monthly_waste == 8.00

def test_finding_to_dict_returns_dict():
    finding = Finding(
        rule="TestRule",
        resource_id="vol-12345",
        region="us-east-1",
        estimated_monthly_waste=8.00,
        details={"size_gb": 100}
    )
    result = finding.to_dict()
    assert isinstance(result, dict)
    assert result["resource_id"] == "vol-12345"

def test_finding_estimated_waste_is_float():
    finding = Finding(
        rule="TestRule",
        resource_id="vol-12345",
        region="us-east-1",
        estimated_monthly_waste=8.00,
        details={}
    )
    assert isinstance(finding.estimated_monthly_waste, float)