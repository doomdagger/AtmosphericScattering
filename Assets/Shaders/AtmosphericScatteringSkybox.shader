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

				float3 lightDir = -_WorldSpaceLightPos0.xyz;

				float3 planetCenter = _CameraPos;
				planetCenter = float3(0, -_PlanetRadius, 0);

				float height = length(rayStart - planetCenter) - _PlanetRadius;
				float3 normal = normalize(rayStart - planetCenter);

				float viewZenith = dot(normal, rayDir);
				float sunZenith = dot(normal, -lightDir);
				float3 coords = float3(ParamHeight(height), ParamViewDirection(viewZenith, height), ParamSunDirection(sunZenith));

				float3 lightInscatter = 0;

				// first order
				float4 scatterR = 0;
				float4 scatterM = 0;
				scatterR = tex3D(_SkyboxLUT, coords);		
				ApproximateMieFromRayleigh(scatterR, scatterM.xyz);
				ApplyPhaseFunctionElek(scatterR.xyz, scatterM.xyz, dot(rayDir, -lightDir.xyz));
				lightInscatter += scatterR + scatterM;

				// second order
				float4 scatterR2 = 0;
				float4 scatterM2 = 0;
				scatterR2 = tex3D(_SkyboxLUT2, coords);
				ApproximateMieFromRayleigh(scatterR2, scatterM2.xyz);
				//ApplyPhaseFunctionElek(scatterR2.xyz, scatterM2.xyz, dot(rayDir, -lightDir.xyz));
				
				//lightInscatter += max(scatterR2.xyz + scatterM2.xyz, 0.0);

				return float4(max(0, lightInscatter), 1);
			}
			ENDCG
		}
	}
}
