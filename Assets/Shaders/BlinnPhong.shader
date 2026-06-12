// Upgrade NOTE: replaced '_World2Object' with 'unity_WorldToObject'

Shader "Unlit/BlinnPhong"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Kd("漫反射系数", Color) = (1,1,1)
        _Ks("镜面反射系数", Color) = (1,1,1)
        _Ka("环境光系数", Color) = (1,1,1)
        _KsPow("镜面反射cos幂次", Float) = 200
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        //前向渲染：对每个物体，依次计算每个光源的影响，然后输出最终颜色
        Pass
        {
            //主光源
            Tags { "LightMode" = "ForwardBase" }
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_base
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_world : TEXCOORD1;
                float4 pos_world : TEXCOORD2;
            };
            
            sampler2D _MainTex;
            float4 _MainTex_ST;

            float3 _Kd;
            float3 _Ks;
            float3 _Ka;
            float _KsPow;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal_world = normalize(mul(v.normal, unity_WorldToObject));
                o.pos_world = mul(unity_ObjectToWorld, v.vertex); //得到顶点的世界坐标
                return o;
            }

            fixed4 frag_base (v2f i) : SV_Target
            {
                fixed3 col = tex2D(_MainTex, i.uv).xyz;

                fixed3 I = _LightColor0;
                float4 light_pos = _WorldSpaceLightPos0;

                float3 normal_world = normalize(i.normal_world);

                float3 l = normalize(light_pos - i.pos_world).xyz; //指向光源的单位向量

                float r = distance(i.pos_world, light_pos);
                float r_square = r * r;

                //漫反射光
                fixed3 Ld = _Kd * col * (I / r_square) * max(0, dot(normal_world, l));

                float3 view_world = normalize(_WorldSpaceCameraPos - i.pos_world.xyz);
                float3 h = normalize(view_world + l);//半程向量

                //镜面反射光
                fixed3 Ls = _Ks * (I / r_square) * pow(max(0, dot(normal_world, h)), _KsPow);

                //环境光
                float3 La = UNITY_LIGHTMODEL_AMBIENT.rgb * col;

                return fixed4(La + Ls + Ld, 1.0);
            }

            ENDCG
        }
        Pass
        {
            //附加光源
            Tags { "LightMode"="ForwardAdd" }

            Blend One One

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_add
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_world : TEXCOORD1;
                float4 pos_world : TEXCOORD2;
            };
            
            sampler2D _MainTex;
            float4 _MainTex_ST;

            float3 _Kd;
            float3 _Ks;
            float3 _Ka;
            float _KsPow;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal_world = normalize(mul(v.normal, unity_WorldToObject));
                o.pos_world = mul(unity_ObjectToWorld, v.vertex); //得到顶点的世界坐标
                return o;
            }

            fixed4 frag_add (v2f i) : SV_Target
            {
                fixed3 col = tex2D(_MainTex, i.uv).xyz;

                fixed3 I = _LightColor0;
                float4 light_pos = _WorldSpaceLightPos0;

                float3 normal_world = normalize(i.normal_world);

                float3 l = normalize(light_pos - i.pos_world).xyz; //指向光源的单位向量

                float r = distance(i.pos_world, light_pos);
                float r_square = r * r;

                //漫反射光
                fixed3 Ld = _Kd * col * (I / r_square) * max(0, dot(normal_world, l));

                float3 view_world = normalize(_WorldSpaceCameraPos - i.pos_world.xyz);
                float3 h = normalize(view_world + l);//半程向量

                //镜面反射光
                fixed3 Ls = _Ks * (I / r_square) * pow(max(0, dot(normal_world, h)), _KsPow);

                return fixed4(Ls + Ld, 1.0);
            }

            ENDCG
        }
    }
}
