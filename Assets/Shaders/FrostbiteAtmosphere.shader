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
				float height = InvParamHeight(i.uv.y);
				float cos_v = InvParamViewDirection(i.uv.x, height);
				float sin_v = sqrt(saturate(1.0 - cos_v * cos_v));
				float3 rayDir = float3(sin_v, cos_v, 0.0);

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
				return PrecomputeGatherSum(i.uv, 0);
			}
			ENDCG
		}
		// pass 2 - Cumulative Gather Sum
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
				return PrecomputeGatherSum(i.uv, 1);
			}
			ENDCG
		}
		// pass 3 - Aerial Perspective
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
				
				float4 inscatter;
				float4 extinction;

				if (linearDepth > 0.99999)
				{
					inscatter = 0;
					extinction = 1;
				}
				else
				{
					float3 wpos = i.wpos;
					float3 rayStart = _WorldSpaceCameraPos;
					float3 rayDir = normalize(wpos - _WorldSpaceCameraPos);

					float3 lightDir = -_WorldSpaceLightPos0.xyz;

					inscatter = tex3D(_InscatteringLUT, float3(uv, linearDepth));
					extinction = tex3D(_ExtinctionLUT, float3(uv, linearDepth));
				}

				float4 color = tex2D(_Background, uv);
				color.rgb = color.rgb * extinction.xyz + inscatter.xyz;
				//color = float4(inscatter.xyz, 1.0);
				return color;
			}
			ENDCG
		}
	}
}
