#define PI 3.14159265359

float _AtmosphereHeight;
float _PlanetRadius;
float2 _DensityScaleHeight;

float3 _ScatteringR;
float3 _ScatteringM;
float3 _ExtinctionR;
float3 _ExtinctionM;

float _MieG;

sampler3D _SkyboxLUT;
sampler3D _SkyboxLUT2;

//-----------------------------------------------------------------------------------------
// InvParamHeight
//-----------------------------------------------------------------------------------------
float InvParamHeight(float u_h)
{
	return u_h * u_h * _AtmosphereHeight;
}

//-----------------------------------------------------------------------------------------
// InvParamViewDirection
//-----------------------------------------------------------------------------------------
float InvParamViewDirection(float u_v, float h)
{
	float c_h = -sqrt(h * (2.0 * _PlanetRadius + h)) / (_PlanetRadius + h);
	if (u_v > 0.5)
	{
		return c_h + pow((u_v-0.5)*2.0, 5.0) * (1.0 - c_h);
	}
	else
	{
		return c_h - pow(u_v*2.0, 5.0) * (1.0 + c_h);
	}
}

//-----------------------------------------------------------------------------------------
// InvParamSunDirection
//-----------------------------------------------------------------------------------------
float InvParamSunDirection(float u_s)
{
	return (tan((2.0 * u_s - 1.0 + 0.26)*0.75)) / (tan(1.26 * 0.75));
}

//-----------------------------------------------------------------------------------------
// ParamViewDirection
//-----------------------------------------------------------------------------------------
float ParamViewDirection(float c_v, float h)
{
	float c_h = -sqrt(h * (2.0 * _PlanetRadius + h)) / (_PlanetRadius + h);
	if (c_v > c_h)
	{
		return 0.5 * pow((c_v - c_h) / (1.0 - c_h), 0.2) + 0.5;
	}
	else
	{
		return 0.5 * pow((c_h - c_v) / (c_h + 1.0), 0.2);
	}
}

//-----------------------------------------------------------------------------------------
// ParamHeight
//-----------------------------------------------------------------------------------------
float ParamHeight(float h)
{
	return pow(h / _AtmosphereHeight, 0.5);
}

//-----------------------------------------------------------------------------------------
// ParamSunDirection
//-----------------------------------------------------------------------------------------
float ParamSunDirection(float c_s)
{
	return 0.5 * ((atan(max(c_s, -0.1975) * tan(1.26*1.1)) / 1.1) + (1 - 0.26));
}

//-----------------------------------------------------------------------------------------
// RaySphereIntersection
//-----------------------------------------------------------------------------------------
float2 RaySphereIntersection(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
{
	rayOrigin -= sphereCenter;
	float a = dot(rayDir, rayDir);
	float b = 2.0 * dot(rayOrigin, rayDir);
	float c = dot(rayOrigin, rayOrigin) - (sphereRadius * sphereRadius);
	float d = b * b - 4 * a * c;
	if (d < 0)
	{
		return -1;
	}
	else
	{
		d = sqrt(d);
		return float2(-b - d, -b + d) / (2 * a);
	}
}

//-----------------------------------------------------------------------------------------
// ApplyPhaseFunctionElek
//-----------------------------------------------------------------------------------------
void ApplyPhaseFunctionElek(inout float3 scatterR, inout float3 scatterM, float cosAngle)
{
	// r
	float phase = (8.0 / 10.0) * ((7.0 / 5.0) + 0.5 * cosAngle);
	scatterR *= phase;

	// m
	float g = _MieG;
	float g2 = g * g;
	phase = ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + cosAngle * cosAngle) / (pow((1 + g2 - 2 * g*cosAngle), 3.0 / 2.0)));
	scatterM *= phase;
}

void ApproximateMieFromRayleigh(in float4 scatterR, out float3 scatterM)
{
    scatterM.xyz = scatterR.xyz * ((scatterR.w) / (scatterR.x)) * (_ScatteringR.x / _ScatteringM.x) * (_ScatteringM / _ScatteringR);
}

float3 GetDirectionFromCos(float cos_value)
{
    return float3(sqrt(saturate(1 - cos_value * cos_value)), cos_value, 0);
}

//-----------------------------------------------------------------------------------------
// PrecomputeTransmittance
//-----------------------------------------------------------------------------------------
half4 PrecomputeTransmittance(float height, float3 rayDir)
{
	float3 planetCenter = float3(0, -_PlanetRadius, 0);
	float3 rayStart = float3(0, height, 0);

	float stepCount = 500;

	float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius);
	if (intersection.x >= 0)
	{
		return 0;
	}

	float rayLength;
	intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
    rayLength = intersection.y;

	float2 currentDensity, previousDensity, totalDensity;
	previousDensity = exp(-(height.xx / _DensityScaleHeight));

	float stepSize = length(rayLength * rayDir) / stepCount;
	for (int step = 1; step <= stepCount; step+=1)
	{
		float3 position = rayStart + step * stepSize * rayDir;

		height = abs(length(position - planetCenter) - _PlanetRadius);

		currentDensity = exp(-(height.xx / _DensityScaleHeight));
		totalDensity += (previousDensity + currentDensity) / 2.0 * stepSize;

		previousDensity = currentDensity;
	}

	half4 transmittance = 1;
	transmittance.xyz = exp(-(totalDensity.x * _ExtinctionR + totalDensity.y * _ExtinctionM));

	return transmittance;
}


//-----------------------------------------------------------------------------------------
// PrecomputeGatherSum
//-----------------------------------------------------------------------------------------
half4 PrecomputeGatherSum(float2 coords)
{
    float stepCount = 64;
    float stepSize = (2.0 * PI) / stepCount;

    float height = InvParamHeight(coords.x);
    float cos_s = InvParamSunDirection(coords.y);

    float3 sunDir = GetDirectionFromCos(cos_s);
    float3 viewDir;

    float4 gathered = 0;
    float4 scatterR;
    float3 scatterM;

    for (int step = 0; step <= stepCount; step+=1)
    {
        float cos_v = cos(step * stepSize);
        viewDir = GetDirectionFromCos(cos_v);
        float u_v = ParamViewDirection(cos_v, height);

        scatterR = tex3D(_SkyboxLUT, float3(coords.x, u_v, coords.y));
        ApproximateMieFromRayleigh(scatterR, scatterM);
        ApplyPhaseFunctionElek(scatterR.xyz, scatterM, dot(viewDir, sunDir));
        gathered.xyz += (scatterR.xyz + scatterM);
    }

    gathered *= 4.0 * PI / stepCount;
    gathered.a = 1.0;
    return gathered;
}