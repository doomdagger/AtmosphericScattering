#define PI 3.14159265359

float _AtmosphereHeight;
float _PlanetRadius;
float4 _DensityScaleHeight;

float3 _ScatteringR;
float3 _ScatteringM;
float3 _ExtinctionR;
float3 _ExtinctionM;
float3 _ExtinctionO;

float _MieG;

sampler3D _SkyboxLUT;
sampler3D _SkyboxLUT2;
sampler3D _SkyboxLUTSingle;

sampler3D _InscatteringLUT;
sampler3D _ExtinctionLUT;

float4 _FrustumCorners[4];

sampler2D _TransmittanceLUT;
float _SunIlluminance;
float4 _LightIrradiance;

float3 _ScatterLUTSize;
float2 _TransmittanceLUTSize;
float2 _GatherSumLUTSize;

static const float SafetyHeightMargin = 16.f;
static const float HeightPower = 0.5f;
static const float ViewZenithPower = 0.2;
static const float SunViewPower = 1.5f;

//-----------------------------------------------------------------------------------------
// GetCosHorizonAnlge
//-----------------------------------------------------------------------------------------
float GetCosHorizonAnlge(float fHeight)
{
    // Due to numeric precision issues, fHeight might sometimes be slightly negative
    fHeight = max(fHeight, 0);
    return -sqrt(fHeight * (2 * _PlanetRadius + fHeight)) / (_PlanetRadius + fHeight);
}

//-----------------------------------------------------------------------------------------
// TexCoord2ZenithAngle
//-----------------------------------------------------------------------------------------
float TexCoord2ZenithAngle(float fTexCoord, float fHeight, in float fTexDim, float power)
{
    float fCosZenithAngle;

    float fCosHorzAngle = GetCosHorizonAnlge(fHeight);
    if (fTexCoord > 0.5)
    {
        // Remap to [0,1] from the upper half of the texture [0.5 + 0.5/fTexDim, 1 - 0.5/fTexDim]
        fTexCoord = saturate((fTexCoord - (0.5f + 0.5f / fTexDim)) * fTexDim / (fTexDim / 2 - 1));
        fTexCoord = pow(fTexCoord, 1 / power);
        // Assure that the ray does NOT hit Earth
        fCosZenithAngle = max((fCosHorzAngle + fTexCoord * (1 - fCosHorzAngle)), fCosHorzAngle + 1e-4);
    }
    else
    {
        // Remap to [0,1] from the lower half of the texture [0.5, 0.5 - 0.5/fTexDim]
        fTexCoord = saturate((fTexCoord - 0.5f / fTexDim) * fTexDim / (fTexDim / 2 - 1));
        fTexCoord = pow(fTexCoord, 1 / power);
        // Assure that the ray DOES hit Earth
        fCosZenithAngle = min((fCosHorzAngle - fTexCoord * (fCosHorzAngle - (-1))), fCosHorzAngle - 1e-4);
    }
    
    return clamp(fCosZenithAngle, -1, +1);
}

//-----------------------------------------------------------------------------------------
// InsctrLUTCoords2WorldParams
//-----------------------------------------------------------------------------------------
void InsctrLUTCoords2WorldParams(in float3 f3UVW,
                                 out float fHeight,
                                 out float fCosViewZenithAngle,
                                 out float fCosSunZenithAngle)
{
    // Rescale to exactly 0,1 range
    f3UVW.xz = saturate((f3UVW * _ScatterLUTSize - 0.5) / (_ScatterLUTSize - 1)).xz;

    f3UVW.x = pow(f3UVW.x, 1 / HeightPower);
    // Allowable height range is limited to [SafetyHeightMargin, AtmTopHeight - SafetyHeightMargin] to
    // avoid numeric issues at the Earth surface and the top of the atmosphere
    fHeight = f3UVW.x * (_AtmosphereHeight - 2 * SafetyHeightMargin) + SafetyHeightMargin;

    fCosViewZenithAngle = TexCoord2ZenithAngle(f3UVW.y, fHeight, _ScatterLUTSize.y, ViewZenithPower);
    
    // Use Eric Bruneton's formula for cosine of the sun-zenith angle
    fCosSunZenithAngle = tan((2.0 * f3UVW.z - 1.0 + 0.26) * 1.1) / tan(1.26 * 1.1);
    fCosSunZenithAngle = clamp(fCosSunZenithAngle, -1, +1);
}

//-----------------------------------------------------------------------------------------
// ZenithAngle2TexCoord
//-----------------------------------------------------------------------------------------
float ZenithAngle2TexCoord(float fCosZenithAngle, float fHeight, in float fTexDim, float power, float fPrevTexCoord)
{
    fCosZenithAngle = fCosZenithAngle;
    float fTexCoord;
    float fCosHorzAngle = GetCosHorizonAnlge(fHeight);
    // When performing look-ups into the scattering texture, it is very important that all the look-ups are consistent
    // wrt to the horizon. This means that if the first look-up is above (below) horizon, then the second look-up
    // should also be above (below) horizon. 
    // We use previous texture coordinate, if it is provided, to find out if previous look-up was above or below
    // horizon. If texture coordinate is negative, then this is the first look-up
    bool bIsAboveHorizon = fPrevTexCoord >= 0.5;
    bool bIsBelowHorizon = 0 <= fPrevTexCoord && fPrevTexCoord < 0.5;
    if (bIsAboveHorizon ||
        !bIsBelowHorizon && (fCosZenithAngle > fCosHorzAngle))
    {
        // Scale to [0,1]
        fTexCoord = saturate((fCosZenithAngle - fCosHorzAngle) / (1 - fCosHorzAngle));
        fTexCoord = pow(fTexCoord, power);
        // Now remap texture coordinate to the upper half of the texture.
        // To avoid filtering across discontinuity at 0.5, we must map
        // the texture coordinate to [0.5 + 0.5/fTexDim, 1 - 0.5/fTexDim]
        //
        //      0.5   1.5               D/2+0.5        D-0.5  texture coordinate x dimension
        //       |     |                   |            |
        //    |  X  |  X  | .... |  X  ||  X  | .... |  X  |  
        //       0     1          D/2-1   D/2          D-1    texel index
        //
        fTexCoord = 0.5f + 0.5f / fTexDim + fTexCoord * (fTexDim / 2 - 1) / fTexDim;
    }
    else
    {
        fTexCoord = saturate((fCosHorzAngle - fCosZenithAngle) / (fCosHorzAngle - (-1)));
        fTexCoord = pow(fTexCoord, power);
        // Now remap texture coordinate to the lower half of the texture.
        // To avoid filtering across discontinuity at 0.5, we must map
        // the texture coordinate to [0.5, 0.5 - 0.5/fTexDim]
        //
        //      0.5   1.5        D/2-0.5             texture coordinate x dimension
        //       |     |            |       
        //    |  X  |  X  | .... |  X  ||  X  | .... 
        //       0     1          D/2-1   D/2        texel index
        //
        fTexCoord = 0.5f / fTexDim + fTexCoord * (fTexDim / 2 - 1) / fTexDim;
    }

    return fTexCoord;
}

//-----------------------------------------------------------------------------------------
// WorldParams2InsctrLUTCoords
//-----------------------------------------------------------------------------------------
float3 WorldParams2InsctrLUTCoords(float fHeight,
                                   float fCosViewZenithAngle,
                                   float fCosSunZenithAngle,
                                   in float3 f3RefUVW)
{
    float3 f3UVW;

    // Limit allowable height range to [SafetyHeightMargin, AtmTopHeight - SafetyHeightMargin] to
    // avoid numeric issues at the Earth surface and the top of the atmosphere
    // (ray/Earth and ray/top of the atmosphere intersection tests are unstable when fHeight == 0 and
    // fHeight == AtmTopHeight respectively)
    fHeight = clamp(fHeight, SafetyHeightMargin, _AtmosphereHeight - SafetyHeightMargin);
    f3UVW.x = saturate((fHeight - SafetyHeightMargin) / (_AtmosphereHeight - 2 * SafetyHeightMargin));
    f3UVW.x = pow(f3UVW.x, HeightPower);

    f3UVW.y = ZenithAngle2TexCoord(fCosViewZenithAngle, fHeight, _ScatterLUTSize.y, ViewZenithPower, f3RefUVW.y);
    
    // Use Eric Bruneton's formula for cosine of the sun-zenith angle
    f3UVW.z = (atan(max(fCosSunZenithAngle, -0.1975) * tan(1.26 * 1.1)) / 1.1 + (1.0 - 0.26)) * 0.5;
    
    f3UVW.xz = ((f3UVW * (_ScatterLUTSize - 1) + 0.5) / _ScatterLUTSize).xz;

    return f3UVW;
}

//-----------------------------------------------------------------------------------------
// TransmitLUTCoords2WorldParams
//-----------------------------------------------------------------------------------------
void TransmitLUTCoords2WorldParams(in float2 f2UV,
                                    out float fHeight,
                                    out float fCosViewZenithAngle)
{
    // Rescale to exactly 0,1 range
    f2UV.xy = saturate((f2UV * _TransmittanceLUTSize - 0.5) / (_TransmittanceLUTSize - 1)).xy;

    f2UV.x = pow(f2UV.x, 1 / HeightPower);
    // Allowable height range is limited to [SafetyHeightMargin, AtmTopHeight - SafetyHeightMargin] to
    // avoid numeric issues at the Earth surface and the top of the atmosphere
    fHeight = f2UV.x * (_AtmosphereHeight - 2 * SafetyHeightMargin) + SafetyHeightMargin;
    
    // Use Eric Bruneton's formula for cosine of the sun-zenith angle
    fCosViewZenithAngle = tan((2.0 * f2UV.y - 1.0 + 0.26) * 1.1) / tan(1.26 * 1.1);
    fCosViewZenithAngle = clamp(fCosViewZenithAngle, -1, +1);
}

//-----------------------------------------------------------------------------------------
// WorldParams2TransmitLUTCoords
//-----------------------------------------------------------------------------------------
float2 WorldParams2TransmitLUTCoords(float fHeight,
                                     float fCosViewZenithAngle)
{
    float2 f2UV;

    // Limit allowable height range to [SafetyHeightMargin, AtmTopHeight - SafetyHeightMargin] to
    // avoid numeric issues at the Earth surface and the top of the atmosphere
    // (ray/Earth and ray/top of the atmosphere intersection tests are unstable when fHeight == 0 and
    // fHeight == AtmTopHeight respectively)
    fHeight = clamp(fHeight, SafetyHeightMargin, _AtmosphereHeight - SafetyHeightMargin);
    f2UV.x = saturate((fHeight - SafetyHeightMargin) / (_AtmosphereHeight - 2 * SafetyHeightMargin));
    f2UV.x = pow(f2UV.x, HeightPower);
    
    // Use Eric Bruneton's formula for cosine of the sun-zenith angle
    f2UV.y = (atan(max(fCosViewZenithAngle, -0.1975) * tan(1.26 * 1.1)) / 1.1 + (1.0 - 0.26)) * 0.5;
    
    f2UV.xy = ((f2UV * (_TransmittanceLUTSize - 1) + 0.5) / _TransmittanceLUTSize).xy;

    return f2UV;
}

//-----------------------------------------------------------------------------------------
// GatherSumLUTCoords2WorldParams
//-----------------------------------------------------------------------------------------
void GatherSumLUTCoords2WorldParams(in float2 f2UV,
                                    out float fHeight,
                                    out float fCosSunZenithAngle)
{
    // Rescale to exactly 0,1 range
    f2UV.xy = saturate((f2UV * _GatherSumLUTSize - 0.5) / (_GatherSumLUTSize - 1)).xy;

    f2UV.x = pow(f2UV.x, 1 / HeightPower);
    // Allowable height range is limited to [SafetyHeightMargin, AtmTopHeight - SafetyHeightMargin] to
    // avoid numeric issues at the Earth surface and the top of the atmosphere
    fHeight = f2UV.x * (_AtmosphereHeight - 2 * SafetyHeightMargin) + SafetyHeightMargin;
    
    // Use Eric Bruneton's formula for cosine of the sun-zenith angle
    fCosSunZenithAngle = tan((2.0 * f2UV.y - 1.0 + 0.26) * 1.1) / tan(1.26 * 1.1);
    fCosSunZenithAngle = clamp(fCosSunZenithAngle, -1, +1);
}

//-----------------------------------------------------------------------------------------
// WorldParams2TransmitLUTCoords
//-----------------------------------------------------------------------------------------
float2 WorldParams2GatherSumLUTCoords(float fHeight,
                                     float fCosSunZenithAngle)
{
    float2 f2UV;

    // Limit allowable height range to [SafetyHeightMargin, AtmTopHeight - SafetyHeightMargin] to
    // avoid numeric issues at the Earth surface and the top of the atmosphere
    // (ray/Earth and ray/top of the atmosphere intersection tests are unstable when fHeight == 0 and
    // fHeight == AtmTopHeight respectively)
    fHeight = clamp(fHeight, SafetyHeightMargin, _AtmosphereHeight - SafetyHeightMargin);
    f2UV.x = saturate((fHeight - SafetyHeightMargin) / (_AtmosphereHeight - 2 * SafetyHeightMargin));
    f2UV.x = pow(f2UV.x, HeightPower);
    
    // Use Eric Bruneton's formula for cosine of the sun-zenith angle
    f2UV.y = (atan(max(fCosSunZenithAngle, -0.1975) * tan(1.26 * 1.1)) / 1.1 + (1.0 - 0.26)) * 0.5;
    
    f2UV.xy = ((f2UV * (_GatherSumLUTSize - 1) + 0.5) / _GatherSumLUTSize).xy;

    return f2UV;
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
    float inv4PI = 1.0 / (4.0 * PI);
	// r
    float phase = inv4PI * (8.0 / 10.0) * ((7.0 / 5.0) + 0.5 * cosAngle);
	scatterR *= phase;

	// m
	float g = _MieG;
	float g2 = g * g;
    phase = inv4PI * ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + cosAngle * cosAngle) / (pow((1 + g2 - 2 * g * cosAngle), 3.0 / 2.0)));
	scatterM *= phase;
}

//-----------------------------------------------------------------------------------------
// ApproximateMieFromRayleigh
//-----------------------------------------------------------------------------------------
void ApproximateMieFromRayleigh(in float4 scatterR, inout float3 scatterM)
{
    if (scatterR.x == 0)
        scatterM = float3(0, 0, 0);
    else
        scatterM = scatterR.xyz * ((scatterR.w) / (scatterR.x)) * (_ScatteringR.x / _ScatteringM.x) * (_ScatteringM.xyz / _ScatteringR.xyz);
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

	float3 currentDensity, previousDensity, totalDensity;
	previousDensity = exp(-(height.xxx / _DensityScaleHeight.xyz));

	float stepSize = length(rayLength * rayDir) / stepCount;
	for (int step = 1; step <= stepCount; step+=1)
	{
		float3 position = rayStart + step * stepSize * rayDir;

		height = abs(length(position - planetCenter) - _PlanetRadius);

		currentDensity = exp(-(height.xxx / _DensityScaleHeight.xyz));
		totalDensity += (previousDensity + currentDensity) / 2.0 * stepSize;

		previousDensity = currentDensity;
	}

	half4 transmittance = 1;
	transmittance.xyz = exp(-(totalDensity.x * _ExtinctionR + totalDensity.y * _ExtinctionM + totalDensity.z * _ExtinctionO));

	return transmittance;
}


//-----------------------------------------------------------------------------------------
// PrecomputeGatherSum
//-----------------------------------------------------------------------------------------
half4 PrecomputeGatherSum(float2 coords)
{
    float stepCount = 64;
    float stepSize = (2.0 * PI) / stepCount;

    float3 viewDir, sunDir;
    float cos_v, cos_s, height;

    GatherSumLUTCoords2WorldParams(coords, height, cos_s);
    sunDir = GetDirectionFromCos(cos_s);

    float4 gathered = 0;
    float4 scatterR;
	float3 scatterM;

    float3 prevLookupCoords, currentLookupCoords;
    prevLookupCoords = float3(0, -1, 0);

    for (int step = 0; step < stepCount; step+=1)
    {
        cos_v = cos(step * stepSize);
        viewDir = GetDirectionFromCos(cos_v);

        currentLookupCoords = WorldParams2InsctrLUTCoords(height, cos_v, cos_s, prevLookupCoords);
        scatterR = tex3D(_SkyboxLUT2, currentLookupCoords);

        prevLookupCoords = currentLookupCoords;

		ApproximateMieFromRayleigh(scatterR, scatterM);
        ApplyPhaseFunctionElek(scatterR.xyz, scatterM, dot(viewDir, sunDir));
        
        gathered += float4(scatterR.xyz + scatterM.xyz, 0.0);
    }

    gathered *= 4.0 * PI / stepCount; // TODO: should multiply 4PI ??
    return gathered;
}

//-----------------------------------------------------------------------------------------
// Limb Darkening
//-----------------------------------------------------------------------------------------
void SunLimbDarkening(float normalizedCenter2Edge, inout float3 luminance)
{
    float3 u = float3(1.0, 1.0, 1.0); // some models have u !=1
    float3 a = float3(0.397, 0.503, 0.652); // coefficient for RGB wavelength (680 ,550 ,440)
    
    float centerToEdge = 1.0 - normalizedCenter2Edge;
    float mu = sqrt(1.0 - centerToEdge * centerToEdge);

    float3 factor = 1.0 - u * (1.0 - pow(mu, a));
    luminance *= factor;

}