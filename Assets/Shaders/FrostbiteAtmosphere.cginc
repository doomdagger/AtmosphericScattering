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

// Height Fog
float3 _HFBetaRs; // Scattering coef. of Rayleigh scattering [1/m]
float _HFBetaMs; // Scattering coef. of Mie scattering [1/m]
float _HFBetaMa; // Absorption coef. of Mie scattering [1/m]
float _HFMieAsymmetry; // Asymmetry factor of Mie scattering [-]
float _HFScaleHeight; // Scale Height [m]
float3 _HFAlbedoR; // Control parameter of Rayleigh scattering color [-]
float3 _HFAlbedoM; // Control parameter of Mie scattering color [-]
// cloud also need this
sampler2D _SunlightLUT;
sampler2D _SkylightLUT;

// Volumetric Cloud Rendering
const float env_inf = 1e10;
const float3 noiseKernel[6] = { { 0.4f, -0.6f, 0.1f }, { 0.2f, -0.3f, -0.2f }, { -0.9f, 0.3f, -0.1f }, { -0.5f, 0.5f, 0.4f }, { -1.0f, 0.3f, 0.2f }, { 0.3f, -0.9f, 0.4f } };

float2 _CloudscapeRange; // 1500, 4000
sampler3D _Cloud3DNoiseTexA;
sampler3D _Cloud3DNoiseTexB;
sampler2D _WeatherTex;
float3 _WindDirection;
float _WindSpeed;
float _SigmaScattering;
float _SigmaExtinction;
float _LowFreqUVScale;
float _HighFreqUVScale;

sampler2D _CloudTexture;

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
		return -env_inf;
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
void ApproximateMieFromRayleigh(in float4 scatterR, out float3 scatterM)
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

    gathered *= 4.0 * PI / stepCount;
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

//-----------------------------------------------------------------------------------------
// PrecomputeSkylight
//-----------------------------------------------------------------------------------------
half4 PrecomputeSkylight(float2 coords)
{
    float stepCount = 64;
    float stepSize = (2.0 * PI) / stepCount;

    float3 viewDir, sunDir;
    float cos_v, cos_s, height;

    TransmitLUTCoords2WorldParams(coords, height, cos_s);
    sunDir = GetDirectionFromCos(cos_s);

    float4 skylight = 0;
    float4 scatterR;
    float3 scatterM;

    float3 prevLookupCoords, currentLookupCoords;
    prevLookupCoords = float3(0, -1, 0);

    for (int step = 0; step < stepCount; step += 1)
    {
        cos_v = cos(step * stepSize);
        viewDir = GetDirectionFromCos(cos_v);

        currentLookupCoords = WorldParams2InsctrLUTCoords(height, cos_v, cos_s, prevLookupCoords);
        scatterR = tex3D(_SkyboxLUT, currentLookupCoords);

        prevLookupCoords = currentLookupCoords;

        ApproximateMieFromRayleigh(scatterR, scatterM);
        ApplyPhaseFunctionElek(scatterR.xyz, scatterM, dot(viewDir, sunDir));
        
        skylight += float4(scatterR.xyz + scatterM.xyz, 0.0) * max(0, dot(float3(0, 1, 0), viewDir));
    }
    
    float3 transZenith = tex2D(_TransmittanceLUT, WorldParams2TransmitLUTCoords(0.0, 1.0)).xyz;
    float3 outerLightIrrad = _LightIrradiance.rgb / transZenith;

    skylight.xyz *= 4.0 * PI / stepCount * outerLightIrrad;
    return skylight;
}

//-----------------------------------------------------------------------------------------
// PrecomputeSkylight
//-----------------------------------------------------------------------------------------
half4 PrecomputeSunlight(float2 coords)
{
    float3 transZenith = tex2D(_TransmittanceLUT, WorldParams2TransmitLUTCoords(0.0, 1.0)).xyz;
    float3 outerLightIrrad = _LightIrradiance.rgb / transZenith;

    float3 transCurrent = tex2D(_TransmittanceLUT, coords).xyz;
    return float4(outerLightIrrad * transCurrent, 0.0);
}

// Height Fog Started
float Rayleigh(float mu)
{
    return 3.0 / 4.0 * 1.0 / (4.0 * PI) * (1.0 + mu * mu);
}

float Mie(float mu, float g)
{
  // Henyey-Greenstein phase function
    return (1.0 - g * g) / ((4.0 * PI) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
}

/*
  Calculates the in-scatter and transmittance of the height fog
    Usage:
    float3 background;
    ...
    float3 inscatter, transmittance;
    HeightFog(.., inscatter, transmittance);
    background = background * transmittance + inscatter;
*/
void ComputeHeightFog(float distanceToCamera, float rayStartHeight, float rayEndHeight, float3 sunColor, float3 ambColor,
                      float cosSunViewAngle, out float3 inscatter, out float3 extinction)
{
    float3 betaT = _HFBetaRs + (_HFBetaMs + _HFBetaMa);

    // transmittance
    float t = max(1e-2, (rayStartHeight - rayEndHeight) / _HFScaleHeight);
    t = (1.0 - exp(-t)) / t * exp(-rayEndHeight / _HFScaleHeight);
    extinction = exp(-distanceToCamera * t * betaT);

    // inscatter
    float3 singleSctrR = _HFAlbedoR * _HFBetaRs * Rayleigh(cosSunViewAngle);
    float3 singleSctrM = _HFAlbedoM * _HFBetaMs * Mie(cosSunViewAngle, _HFMieAsymmetry);
    
    inscatter = sunColor * (singleSctrR + singleSctrM);
    inscatter += ambColor * (_HFBetaRs + _HFBetaMs);
    inscatter /= betaT;
    inscatter *= (1.0 - extinction);
}

//-----------------------------------------------------------------------------------------
// Volumetric Cloud Rendering
//-----------------------------------------------------------------------------------------

float3 GetWeather(float3 position)
{
    float2 uv = position.xz * 0.00001 + 0.5;
    return tex2Dlod(_WeatherTex, float4(uv, 0.0, 0.0)).rgb;
}

float GetHeightFractionForPoint(float height)
{
    float heightFraction = (height - _CloudscapeRange.x) / (_CloudscapeRange.y - _CloudscapeRange.x);
    return saturate(heightFraction);
}

float GetDensityHeightGradientForPoint(float heightFract, float cloudType)
{
    const float4 CloudGradient1 = float4(0.0, 0.05, 0.1, 0.2);
    const float4 CloudGradient2 = float4(0.0, 0.2, 0.4, 0.8);
    const float4 CloudGradient3 = float4(0.0, 0.1, 0.6, 0.9);

    float a = 1.0 - saturate(cloudType * 2.0);
    float b = 1.0 - abs(cloudType - 0.5) * 2.0;
    float c = saturate(cloudType - 0.5) * 2.0;

    float4 gradientInfo = CloudGradient1 * a + CloudGradient2 * b + CloudGradient3 * c;
    return smoothstep(gradientInfo.x, gradientInfo.y, heightFract) - smoothstep(gradientInfo.z, gradientInfo.w, heightFract);
}

float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + saturate((original_value - original_min) / (original_max - original_min) * (new_max - new_min));
}

void AnimateCloud(inout float3 position, float heightFract)
{
    float3 windDir = normalize(_WindDirection);
    float cloudTopOffset = 500.0;
    // Skew in wind direction
    position += heightFract * windDir * cloudTopOffset;
    // Animate clouds in wind direction and add a small upward bias
    // to the wind direction
    position += (windDir + float3(0, 1, 0)) * _WindSpeed * _Time.x * 1000;
}

float SampleCloudDensity(float3 position, float height, float3 weatherInfo, bool useSimpleSample)
{
    float BaseFreq = 1e-4;
	float3 coordOffset = float3(0.1 * 20, -_Time.x * 0.15, 0.092 * 20);
	//float3 coordOffset = 0.0;
	// Get fraction height
    float heightFract = GetHeightFractionForPoint(height);
    // animate cloud
    AnimateCloud(position, heightFract);
    // Read the low-frequency Perlin-Worley and Worley noises.
    float4 lowFrequencyNoises = tex3D(_Cloud3DNoiseTexA, position * BaseFreq * _LowFreqUVScale + coordOffset).rgba;
    // Build an FBM out of the low frequency Worley noises that can be 
    // used to add detail to the low-frequency Perlin-Worley noise.
    float lowFreqFBM = lowFrequencyNoises.g * 0.625f + lowFrequencyNoises.b * 0.25f + lowFrequencyNoises.a * 0.125f;
    // define the base cloud shape by dilating it with the low-frequency
    // FBM made of Worley noise.
    float baseCloud = Remap(lowFrequencyNoises.r, -(1.0 - lowFreqFBM), 1.0, 0.0, 1.0);
    // Get the density-height gradient using the density height function
    float densityHeightGradient = GetDensityHeightGradientForPoint(heightFract, weatherInfo.b);
    // Apply the height function to the base cloud shape.
    baseCloud *= densityHeightGradient;
    // Cloud coverage is stored in weatherInfo's red channel
    float cloudCoverage = 1.0 - weatherInfo.r;
    // Use remap to apply the cloud coverage attribute
    float baseCloudWithCoverage = Remap(baseCloud, cloudCoverage, 1.0, 0.0, 1.0);
    // Apply cloud coverage
    baseCloudWithCoverage *= baseCloudWithCoverage;
    // whether use full sample or not
    if (useSimpleSample)
    {
        return saturate(baseCloudWithCoverage);
    }
    else
    {
        // TODO: xy turbulence from curl noise
        // position.xy += curlNoise.xy * (1.0 - heightFract);
        // Sample high-frequency noises
        float3 highFrequencyNoises = tex3D(_Cloud3DNoiseTexB, position * BaseFreq * _HighFreqUVScale + coordOffset).rgb;
        // Build high-frequency Worley noise FBM
        float highFreqFBM = highFrequencyNoises.r * 0.625 + highFrequencyNoises.g * 0.25 + highFrequencyNoises.b * 0.125;
        // Transition from wispy shapes to billowy shapes over height
        float highFreqNoiseModifier = lerp(highFreqFBM, 1.0 - highFreqFBM, saturate(heightFract * 10.0));
        // Erode the base cloud shape with the high-frequency Worley noises
        float finalCloud = Remap(baseCloudWithCoverage, highFreqNoiseModifier * 0.2, 1.0, 0.0, 1.0);
        return saturate(finalCloud);
    }
}

float HenyeyGreenstein(float cosSunViewAngle, float inG)
{
    float g2 = inG * inG;
    return (1.0 - g2) / ((4.0 * PI) * pow(1.0 + g2 - 2.0 * inG * cosSunViewAngle, 1.5));
}

float TwoLobesHGPhaseFunction(float cosSunViewAngle)
{
    // two-lobes HG phase function from frostbite
    float g0 = 0.8;
    float g1 = -0.5;
    float alpha = 0.5;
    return lerp(HenyeyGreenstein(cosSunViewAngle, g0), HenyeyGreenstein(cosSunViewAngle, g1), alpha);
}

float Beer(float opticalDepth, float precipitation)
{
    float beer = exp(-opticalDepth);
	return beer;
}

float Powder(float opticalDepth)
{
	float powder =1.0 - saturate(exp(-2.0 * opticalDepth));
	return powder;
}

float SampleCloudDensityAlongCone(float3 position, float3 sunDir, float3 planetCenter)
{
    const float LightSampleLength = 10.0;
    float3 lightStep = sunDir * LightSampleLength;
    // How wide to make the cone
    float coneSpreadMultiplier = LightSampleLength;
    
    float densityAlongCone = 0.0;
    float opticalDepth = 0.0;

    float height;
    float3 samplePosition;
    float3 weatherInfo;
    float curSampleDensity;

    [loop]
    for (int i = 0; i < 6; i+=1)
    {
        position += lightStep;
        samplePosition = position + (coneSpreadMultiplier * noiseKernel[i] * float(i + 1));
        height = length(samplePosition - planetCenter) - _PlanetRadius;
        weatherInfo = GetWeather(samplePosition);
        if (densityAlongCone < 0.3)
        {
            curSampleDensity = SampleCloudDensity(samplePosition, height, weatherInfo, false);
        }
        else
        {
            curSampleDensity = SampleCloudDensity(samplePosition, height, weatherInfo, true);
        }
        opticalDepth += curSampleDensity * LightSampleLength;
        densityAlongCone += curSampleDensity;
    }
    // account for shadows cast from distant clouds onto the part of the cloud 
    // for which we are calculating lighting, we take one long distance sample
    position += lightStep * 3.0;
    height = length(position - planetCenter) - _PlanetRadius;
    weatherInfo = GetWeather(position);
    
    curSampleDensity = SampleCloudDensity(position, height, weatherInfo, true);
    opticalDepth += curSampleDensity * (LightSampleLength * 3.0);
	densityAlongCone += curSampleDensity;

    return densityAlongCone;
}

float exponential_integral(float z)
{
    return 0.5772156649015328606065 + log(1e-4 + abs(z)) + z * (1.0 + z * (0.25 + z * ((1.0 / 18.0) + z * ((1.0 / 96.0) + z * (1.0 / 600.0))))); // For x!=0
}

float3 CalculateAmbientLighting(float height, float3 sunlight, float3 skylight, float extinction_coeff)
{
    float3 CloudTopColor = float3(0.93, 0.93, 0.93);
    float3 CloudBaseColor = float3(0.93, 0.93, 0.93);

    float heightFract = GetHeightFractionForPoint(height);

    float ambient_term = 0.6 * saturate(1.0 - heightFract);
    float3 isotropic_scattering_top = (CloudTopColor.rgb * sunlight.rgb) * max(0.0, exp(ambient_term) - ambient_term * exponential_integral(ambient_term));

    ambient_term = -extinction_coeff * heightFract;
    float3 isotropic_scattering_bottom = (CloudBaseColor.rgb * skylight.rgb) * max(0.0, exp(ambient_term) - ambient_term * exponential_integral(ambient_term)) * 1.5;

    isotropic_scattering_top *= saturate(heightFract);

    return isotropic_scattering_bottom + isotropic_scattering_top;
}

float4 RaymarchingCloud(float3 rayStart, float3 rayDir, float3 sunDir, float3 planetCenter)
{
    float2 hitDistance;
    float2 hitScapeBottom = RaySphereIntersection(rayStart, rayDir, planetCenter, _CloudscapeRange.x + _PlanetRadius);
    float2 hitScapeTop = RaySphereIntersection(rayStart, rayDir, planetCenter, _CloudscapeRange.y + _PlanetRadius);
    float3 normal = normalize(rayStart - planetCenter);
    float rayStartHeight = length(rayStart - planetCenter) - _PlanetRadius;

    // camera below cloudscape bottom
    if (rayStartHeight < _CloudscapeRange.x)
    {
        hitDistance = float2(hitScapeBottom.y, hitScapeTop.y);
        // if hit ground, do not compute cloud ray-marching
        if (rayDir.y < 0.0f)
        {
            float h = rayStart.y + _PlanetRadius;
            h = h * h * (1.0 - rayDir.y * rayDir.y) - _PlanetRadius * _PlanetRadius;
            if (h <= 0.0f)
            {
                // do not compute anything
                return 0.0;
            }
        }
    }
    // camera above cloudscape top
    else if (rayStartHeight > _CloudscapeRange.y)
    {
		// do not compute anything
		return 0.0;
    }
    // camera inside cloudscape
    else
    {
		// do not compute anything
		return 0.0;
    }
    // clamp distance range
	hitDistance.x = max(0.0, hitDistance.x);
	// TODO: remove in the future
	//hitDistance.y = min(1e4, hitDistance.y);
	if (hitDistance.y - hitDistance.x < 0.0)
		return 0.0;

    float cosSunViewAngle = dot(rayDir, sunDir);
    float cosSunZenithAngle = dot(normal, sunDir);
    // more steps when looking toward horizon
    int stepCount = int(lerp(128.0f, 64.0f, saturate(rayDir.y)));
    float3 step = rayDir * (hitDistance.y - hitDistance.x) / stepCount;
    float stepLength = length(step);
    // march slightly above cloudscape bottom layer
    float3 position = rayStart + rayDir * hitDistance.x + 0.5 * step;
    float3 weatherInfo = GetWeather(position);
    float height = length(position - planetCenter) - _PlanetRadius;
    
    float cloudTest = 0.0;
    float3 scatteredLight = 0.0;
    float transmittance = 1.0;
    float sampleSigmaS, sampleSigmaE, Tr;
    float sampledDensity, opticalDepthAlongCone;
    float2 lutCoords;
    float3 sunLight, ambLight, skyLight;
    float3 S, Sint;
    
    float totalDensity = 0.0;
	float opticalDepth = 0.0;
	lutCoords = WorldParams2TransmitLUTCoords(0.0, 1.0);
	float3 BaseSunIrradiance = _LightIrradiance.rgb / tex2D(_TransmittanceLUT, lutCoords).rgb;

    [loop]
    for (int i = 0; i < stepCount; i+=1)
    {
        // Sample density the cheap way
        cloudTest = SampleCloudDensity(position, height, weatherInfo, true);
        // if we are still potentially in the cloud
        if (cloudTest > 0.0)
        {
            // Sample density the expensive way
            sampledDensity = SampleCloudDensity(position, height, weatherInfo, false);
            totalDensity += sampledDensity;
			opticalDepth += sampledDensity * stepLength;
            // use current height, sun-------------->cloud-------------->camera
            //                          atmosphere          atmosphere
            lutCoords = WorldParams2TransmitLUTCoords(height, cosSunZenithAngle);
            sunLight = BaseSunIrradiance * tex2D(_TransmittanceLUT, lutCoords).rgb;
            skyLight = tex2D(_SkylightLUT, lutCoords).rgb;
            ambLight = CalculateAmbientLighting(height, sunLight, skyLight, 2e-2);
            // walks in the given direction from the start point and takes
            // 6 lighting samples inside the cone                   
            opticalDepthAlongCone = SampleCloudDensityAlongCone(position, sunDir, planetCenter);
            sunLight *= Beer(opticalDepthAlongCone, weatherInfo.g) * Powder(opticalDepthAlongCone) * 2.0;
            ambLight *= Powder(opticalDepthAlongCone) * 0.2;

            sampleSigmaS = (2e-2) * sampledDensity;
            sampleSigmaE = (2e-2) * sampledDensity + 0.0000001;
            S = (sunLight * TwoLobesHGPhaseFunction(cosSunViewAngle) + ambLight) * sampleSigmaS;
            Tr = Beer(sampleSigmaE * stepLength, weatherInfo.g);
            Sint = (S - S * Tr) / (sampleSigmaE);
            scatteredLight += transmittance * Sint;
            transmittance *= Tr;
        }
        // update location info
        position += step;
        height = length(position - planetCenter) - _PlanetRadius;
        weatherInfo = GetWeather(position);
    }

    return float4(scatteredLight, 1.0 - exp(-2 * 0.005f * opticalDepth));

}