using UnityEngine;

public class EllipticalLightMotionOnPlane : MonoBehaviour
{
    [Header("平面参数")]
    [Tooltip("平面方程 x + y + z = a 中的 a 值")]
    public float planeA = 5f;
    
    [Header("椭圆参数")]
    [Tooltip("椭圆半长轴")]
    public float semiMajorAxis = 3f;
    
    [Tooltip("椭圆半短轴")]
    public float semiMinorAxis = 2f;
    
    [Tooltip("椭圆在平面上的倾斜角 (度)")]
    [Range(0f, 180f)]
    public float tiltAngle = 45f;
    
    [Header("运动参数")]
    [Tooltip("运动速度 (弧度/秒)")]
    public float speed = 1f;
    
    [Header("可视化")]
    [Tooltip("是否在Scene视图中绘制椭圆轨迹")]
    public bool drawTrajectory = true;
    
    [Tooltip("轨迹线段数量")]
    public int segments = 100;
    
    private float angle = 0f;
    
    // 平面上的两个正交基向量
    private Vector3 u;  // 椭圆长轴方向
    private Vector3 v;  // 椭圆短轴方向
    private Vector3 planeCenter;  // 平面中心点 (椭圆中心)
    
    void Start()
    {
        UpdatePlaneBasis();
    }
    
    void UpdatePlaneBasis()
    {
        // 平面的法向量是 (1, 1, 1)
        Vector3 normal = new Vector3(1, 1, 1).normalized;
        
        // 找一个与法向量垂直的向量作为 u 的初始方向
        // 取 (1, -1, 0) 作为参考，它与 (1,1,1) 的点积 = 0
        Vector3 tempU = new Vector3(1, -1, 0).normalized;
        
        // v 由法向量和 u 叉乘得到
        Vector3 tempV = Vector3.Cross(normal, tempU).normalized;
        
        // 应用倾斜旋转：在平面内旋转 u 和 v
        float rad = tiltAngle * Mathf.Deg2Rad;
        float cosT = Mathf.Cos(rad);
        float sinT = Mathf.Sin(rad);
        
        u = (tempU * cosT - tempV * sinT).normalized;
        v = (tempU * sinT + tempV * cosT).normalized;
        
        // 计算椭圆中心（使椭圆过原点需要特殊处理，这里先放在平面上）
        // 我们需要找到一个点使得椭圆经过原点 (0,0,0)
        // 原点满足 x+y+z=0，所以只有当 a=0 时原点才在平面上
        // 当 a ≠ 0 时，原点不在平面上，椭圆不可能过原点
        
        // 椭圆中心选在平面上的一个合适位置
        // 我们让椭圆的一个端点经过平面与某条轴的交点
        Vector3 planeNormal = normal;
        float d = -planeA;  // 平面方程: x + y + z - a = 0，即 planeNormal·P = planeA/√3
        
        // 平面中心点 (使计算方便)
        // 取平面内离原点最近的点作为参考中心
        planeCenter = planeNormal * (planeA / Mathf.Sqrt(3));
    }
    
    void Update()
    {
        // 更新角度
        angle += speed * Time.deltaTime;
        if (angle > Mathf.PI * 2f)
            angle -= Mathf.PI * 2f;
        
        // 计算椭圆上的局部坐标
        float x_local = semiMajorAxis * Mathf.Cos(angle);
        float z_local = semiMinorAxis * Mathf.Sin(angle);
        
        // 变换到平面上的世界坐标
        Vector3 planePos = planeCenter + u * x_local + v * z_local;
        
        transform.position = planePos;
    }
    
    void OnDrawGizmos()
    {
        if (!drawTrajectory) return;
        
        // 确保基向量更新
        Vector3 normal = new Vector3(1, 1, 1).normalized;
        Vector3 tempU = new Vector3(1, -1, 0).normalized;
        Vector3 tempV = Vector3.Cross(normal, tempU).normalized;
        
        float rad = tiltAngle * Mathf.Deg2Rad;
        float cosT = Mathf.Cos(rad);
        float sinT = Mathf.Sin(rad);
        
        Vector3 drawU = (tempU * cosT - tempV * sinT).normalized;
        Vector3 drawV = (tempU * sinT + tempV * cosT).normalized;
        
        Vector3 drawCenter = normal * (planeA / Mathf.Sqrt(3));
        
        Gizmos.color = Color.yellow;
        
        Vector3[] points = new Vector3[segments + 1];
        
        for (int i = 0; i <= segments; i++)
        {
            float t = (float)i / segments * Mathf.PI * 2f;
            float x_local = semiMajorAxis * Mathf.Cos(t);
            float z_local = semiMinorAxis * Mathf.Sin(t);
            
            Vector3 pos = drawCenter + drawU * x_local + drawV * z_local;
            points[i] = pos;
        }
        
        // 绘制椭圆轨迹
        for (int i = 0; i < segments; i++)
        {
            Gizmos.DrawLine(points[i], points[i + 1]);
        }
        
        // 绘制平面辅助线（显示平面的范围）
        Gizmos.color = new Color(0.5f, 0.5f, 0.5f, 0.3f);
        DrawPlaneVisualization(normal);
        
        // 绘制椭圆中心点
        Gizmos.color = Color.red;
        Gizmos.DrawWireSphere(drawCenter, 0.1f);
        
        // 绘制椭圆长轴方向指示线
        Gizmos.color = Color.red;
        Vector3 longAxisStart = drawCenter - drawU * semiMajorAxis;
        Vector3 longAxisEnd = drawCenter + drawU * semiMajorAxis;
        Gizmos.DrawLine(longAxisStart, longAxisEnd);
        
        // 绘制椭圆短轴方向指示线
        Gizmos.color = Color.green;
        Vector3 shortAxisStart = drawCenter - drawV * semiMinorAxis;
        Vector3 shortAxisEnd = drawCenter + drawV * semiMinorAxis;
        Gizmos.DrawLine(shortAxisStart, shortAxisEnd);
        
        // 绘制平面方程标签（仅用于调试）
        #if UNITY_EDITOR
        UnityEditor.Handles.Label(drawCenter + Vector3.up * 0.5f, 
            $"x+y+z = {planeA:F1}");
        #endif
    }
    
    void DrawPlaneVisualization(Vector3 normal)
    {
        // 绘制一个网格来可视化平面
        Vector3 center = normal * (planeA / Mathf.Sqrt(3));
        
        // 在平面内找两个正交向量用于绘制网格
        Vector3 uGrid = new Vector3(1, -1, 0).normalized;
        Vector3 vGrid = Vector3.Cross(normal, uGrid).normalized;
        
        float gridSize = Mathf.Max(semiMajorAxis, semiMinorAxis) * 1.5f;
        int gridLines = 5;
        
        Gizmos.color = new Color(0.5f, 0.5f, 0.5f, 0.2f);
        
        for (int i = -gridLines; i <= gridLines; i++)
        {
            float offset = (float)i / gridLines * gridSize;
            Vector3 startU = center + uGrid * offset - vGrid * gridSize;
            Vector3 endU = center + uGrid * offset + vGrid * gridSize;
            Vector3 startV = center + vGrid * offset - uGrid * gridSize;
            Vector3 endV = center + vGrid * offset + uGrid * gridSize;
            
            Gizmos.DrawLine(startU, endU);
            Gizmos.DrawLine(startV, endV);
        }
    }
}