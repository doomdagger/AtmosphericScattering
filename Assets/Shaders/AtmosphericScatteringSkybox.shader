// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

//  Copyright(c) 2016, Michal Skalsky
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its contributors
//     may be used to endorse or promote products derived from this software without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.IN NO EVENT
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
//  TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


Shader "Skybox/AtmosphericScattering"
{
	SubShader
	{
		Tags{ "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" }
		Cull Off ZWrite Off

		Pass
		{
			CGPROGRAM
			#pragma shader_feature ATMOSPHERE_REFERENCE
			#pragma shader_feature RENDER_SUN
			#pragma shader_feature HIGH_QUALITY
			
			#pragma vertex vert
			#pragma fragment frag

			#pragma target 5.0
			
			#include "UnityCG.cginc"
			#include "FrostbiteAtmosphere.cginc"

			float3 _CameraPos;
			
			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct v2f
			{
				float4	pos		: SV_POSITION;
				float3	vertex	: TEXCOORD0;
			};
			
			v2f vert (appdata v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.vertex = v.vertex;
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				float3 rayStart = _CameraPos;
				float3 rayDir = normalize(mul((float3x3)unity_ObjectToWorld, i.vertex));

				float3 lightDir = _WorldSpaceLightPos0.xyz;

				float3 planetCenter = _CameraPos;
				planetCenter = float3(0, -_PlanetRadius, 0);

				float height = length(rayStart - planetCenter) - _PlanetRadius;
				float3 normal = normalize(rayStart - planetCenter);

				float viewZenith = dot(normal, rayDir);
				float sunZenith = dot(normal, lightDir);
				float3 coords = WorldParams2InsctrLUTCoords(height, viewZenith, sunZenith, float3(0, -1, 0));

				float4 scatterR = 0;
				float4 scatterM = 0;
#ifdef ATMOSPHERE_REFERENCE
				scatterR = tex3D(_SkyboxLUTSingle, coords);
#else
				scatterR = tex3D(_SkyboxLUT, coords);
#endif
				ApproximateMieFromRayleigh(scatterR, scatterM.xyz);
				ApplyPhaseFunctionElek(scatterR.xyz, scatterM.xyz, dot(rayDir, lightDir.xyz));

				float3 lightInscatter = scatterR + scatterM;

				float3 transZenith = tex2D(_TransmittanceLUT, WorldParams2TransmitLUTCoords(0.0, 1.0)).xyz;
				lightInscatter *= _LightIrradiance.rgb / transZenith;

				//float3 transCurrent = tex2D(_TransmittanceLUT, coords.xz).xyz;

				//float sunAngularDiameter = 0.545 / 180.0 * PI * 2;
				//if (dot(rayDir, lightDir) > cos(sunAngularDiameter))
				//{
				//	float3 sunColor = _SunIlluminance / (2 * PI * (1 - cos(0.5 * (0.545 / 180 * PI))));
				//	sunColor = transCurrent / transZenith * 100;

				//	float centerToEdge = (dot(rayDir, lightDir) - cos(sunAngularDiameter)) / (1.0 - cos(sunAngularDiameter));
				//	SunLimbDarkening(centerToEdge, sunColor);

				//	return float4(sunColor + lightInscatter, 1.0);
				//}

				float4 screenPos = UnityObjectToClipPos(float4(i.vertex, 1.0));
				screenPos /= screenPos.w;
				// Cloud Related
				screenPos.y *= -1;
				float2 cloudUV = (screenPos.xy + 1.0) / 2.0;
				float4 cloudColor = tex2D(_CloudTexture, cloudUV);

				float3 finalColor = lightInscatter * (1 - cloudColor.a) + cloudColor.rgb;

				return float4(finalColor.xyz, 1);
			}
			ENDCG
		}
	}
}
