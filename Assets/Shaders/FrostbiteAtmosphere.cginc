#define PI 3.14159265359

float _AtmosphereHeight;
float _PlanetRadius;
float2 _DensityScaleHeight;

float3 _ScatteringR;
float3 _ScatteringM;
float3 _ExtinctionR;
float3 _ExtinctionM;

float4 _IncomingLight;
float _MieG;

float4 _FrustumCorners[4];

float _SunIntensity;

sampler2D _TransmittanceLUT;

sampler3D _SkyboxLUT;
sampler3D _SkyboxLUT2;

sampler3D _InscatteringLUT;
sampler3D _ExtinctionLUT;

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
	float phase = (8.0 / 10.0) / (4 * PI) * ((7.0 / 5.0) + 0.5 * cosAngle);
	scatterR *= phase;

	// m
	float g = _MieG;
	float g2 = g * g;
	phase = (1.0 / (4.0 * PI)) * ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + cosAngle * cosAngle) / (pow((1 + g2 - 2 * g*cosAngle), 3.0 / 2.0)));
	scatterM *= phase;
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
	if (intersection.x > 0)
	{
		return 0;
	}

	float rayLength;
	intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);

	if (height > _AtmosphereHeight)
	{
		rayLength = intersection.x;
	}
	else
	{
		rayLength = intersection.y;
	}

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
	transmittance.xyz = exp(-(totalDensity.x * _ExtinctionR + totalDensity.y * _ExtinctionR));

	return transmittance;
}

