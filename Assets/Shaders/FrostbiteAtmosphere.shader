Shader "Hidden/FrostbiteAtmosphere"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_ZTest ("ZTest", Float) = 0
	}
	SubShader
	{
		Tags { "RenderType" = "Opaque" }
		LOD 100

		// No culling or depth
		Cull Off ZWrite Off ZTest Off Blend Off

		CGINCLUDE
		#include "UnityCG.cginc"
		#include "UnityDeferredLibrary.cginc"

		#include "FrostbiteAtmosphere.cginc"
		ENDCG

		// pass 0 - transmittance
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}
			
			half4 frag (v2f i) : SV_Target
			{
				float height, cos_v;
				TransmitLUTCoords2WorldParams(i.uv, height, cos_v);
				float3 rayDir = GetDirectionFromCos(cos_v);

				half4 transmittance = PrecomputeTransmittance(height, rayDir);
				return transmittance;
			}
			ENDCG
		}

		// pass 1 - Gather Sum
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			half4 frag(v2f i) : SV_Target
			{
				return PrecomputeGatherSum(i.uv);
			}
			ENDCG
		}

		// pass 2 - Aerial Perspective
		Pass
		{
			ZTest Always Cull Off ZWrite Off
			Blend One Zero
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				uint vertexId : SV_VertexID;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 wpos : TEXCOORD1;
			};

			sampler2D _Background;

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				o.wpos = _FrustumCorners[v.vertexId];
				return o;
			}

			float4 frag(v2f i) : SV_Target
			{
				float2 uv = i.uv.xy;
				float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
				float linearDepth = Linear01Depth(depth);
				
				float3 rayStart = _WorldSpaceCameraPos;
				float3 rayDir = i.wpos - rayStart;
				float3 rayEnd = rayStart + linearDepth * rayDir;
				float distanceToCamera = length(linearDepth * rayDir);
				
				rayDir = normalize(rayDir);
				float3 sunDir = normalize(-_LightDir.xyz);

				float3 planetCenter = float3(0, -_PlanetRadius, 0);
				float rayStartHeight = length(rayStart - planetCenter) - _PlanetRadius;
				float rayEndHeight = length(rayEnd - planetCenter) - _PlanetRadius;
				float3 normal = normalize(rayStart - planetCenter);

				float sunViewZenith = dot(rayDir, sunDir);
				float sunZenith = dot(normal, sunDir);

				float2 coords = WorldParams2TransmitLUTCoords(rayStartHeight, sunZenith);
				float3 sunColor = tex2D(_SunlightLUT, coords).rgb;
				float3 ambColor = tex2D(_SkylightLUT, coords).rgb;

				float4 inscatter;
				float4 extinction;
				ComputeHeightFog(distanceToCamera, rayStartHeight, rayEndHeight, sunColor, ambColor, sunViewZenith, inscatter.xyz, extinction.xyz);

				float4 color = tex2D(_Background, uv);
				color.rgb = color.rgb * extinction.xyz + inscatter.xyz;
				//color.rgb = color.xyz * extinction.xyz;
				return color;
			}
			ENDCG
		}
		
		// pass 3 - skylight
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}
			
			half4 frag (v2f i) : SV_Target
			{
				half4 skylight = PrecomputeSkylight(i.uv);
				return skylight;
			}
			ENDCG
		}

		// pass 4 - sunlight
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}
			
			half4 frag (v2f i) : SV_Target
			{
				half4 skylight = PrecomputeSunlight(i.uv);
				return skylight;
			}
			ENDCG
		}

		// pass 5 - cloud texture
		Pass
		{
			ZTest Always Cull Off ZWrite Off
			Blend One Zero
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				uint vertexId : SV_VertexID;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 wpos : TEXCOORD1;
			};

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				o.wpos = _FrustumCorners[v.vertexId];
				return o;
			}

			float4 frag(v2f i) : SV_Target
			{
				float2 uv = i.uv.xy;
				float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
				float linearDepth = Linear01Depth(depth);

				float3 rayStart = _WorldSpaceCameraPos;
				float3 rayDir = normalize(i.wpos - rayStart);
				float3 sunDir = normalize(-_LightDir.xyz);

				float3 planetCenter = float3(0, -_PlanetRadius, 0);
				
				// determine intersection information
				return RaymarchingCloud(rayStart, rayDir, sunDir, planetCenter);
			}
			ENDCG
		}
	}
}
