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
			
			sampler2D _MainTex;

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
	}
}
