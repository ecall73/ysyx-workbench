import sys
from PIL import Image

def bmp_to_hex(bmp_file, hex_file):
    try:
        # 打开图像并转换为RGB模式
        img = Image.open(bmp_file).convert('RGB')
        width, height = img.size
        
        # 写入HEX文件
        with open(hex_file, 'w') as f:
            # 写入起始地址
            f.write("@000000\n")
            
            # 逐像素写入颜色值
            for x in range(width):
                for y in range(height):
                    r, g, b = img.getpixel((x, y))
                    # 格式化为6位十六进制数
                    f.write(f"{r:02X}{g:02X}{b:02X}\n")
        
        print(f"转换完成: {bmp_file} -> {hex_file}")
        print(f"图像尺寸: {width}x{height}, 总像素数: {width*height}")
        
    except Exception as e:
        print(f"错误: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("使用方法: python3 bmp2hex.py <输入bmp文件> <输出hex文件>")
        sys.exit(1)
    
    bmp_file = sys.argv[1]
    hex_file = sys.argv[2]
    bmp_to_hex(bmp_file, hex_file)