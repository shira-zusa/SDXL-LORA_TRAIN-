# deepbooru_gui.py
# DeepDanbooru GUI 打标工具 - 修复重复问题版本

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import sys
import os
from PIL import Image, ImageTk
import json
import glob
from datetime import datetime

# 添加当前目录到Python路径
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

try:
    from deepdanbooru import DeepDanbooruModel
except ImportError:
    print("错误: 无法导入 deepdanbooru 模块")
    print("请确保 deepdanbooru.py 文件在当前目录")
    sys.exit(1)

class DeepDanbooruGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("DeepDanbooru 图片打标工具")
        self.root.geometry("1000x700")
        
        # 模型变量
        self.model = None
        self.model_loaded = False
        
        # 图片相关变量
        self.current_image_path = None
        self.image_files = []
        self.current_index = 0
        
        # 输出格式
        self.output_format = tk.StringVar(value="jsonl")
        
        # 阈值
        self.threshold = tk.DoubleVar(value=0.5)
        
        self.setup_ui()
        self.load_model()
    
    def setup_ui(self):
        """设置用户界面"""
        # 主框架
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 配置网格权重
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)
        main_frame.rowconfigure(2, weight=1)
        
        # 标题
        title_label = ttk.Label(main_frame, text="DeepDanbooru 图片打标工具", 
                               font=("Arial", 16, "bold"))
        title_label.grid(row=0, column=0, columnspan=3, pady=(0, 20))
        
        # 控制面板
        control_frame = ttk.LabelFrame(main_frame, text="控制面板", padding="10")
        control_frame.grid(row=1, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=(0, 10))
        control_frame.columnconfigure(1, weight=1)
        
        # 选择输入文件夹
        ttk.Label(control_frame, text="输入文件夹:").grid(row=0, column=0, sticky=tk.W, padx=(0, 10))
        self.input_path_var = tk.StringVar()
        ttk.Entry(control_frame, textvariable=self.input_path_var, state="readonly").grid(row=0, column=1, sticky=(tk.W, tk.E))
        ttk.Button(control_frame, text="浏览", command=self.select_input_folder).grid(row=0, column=2, padx=(10, 0))
        
        # 选择输出文件夹
        ttk.Label(control_frame, text="输出文件夹:").grid(row=1, column=0, sticky=tk.W, padx=(0, 10))
        self.output_path_var = tk.StringVar()
        ttk.Entry(control_frame, textvariable=self.output_path_var, state="readonly").grid(row=1, column=1, sticky=(tk.W, tk.E))
        ttk.Button(control_frame, text="浏览", command=self.select_output_folder).grid(row=1, column=2, padx=(10, 0))
        
        # 输出格式选择
        ttk.Label(control_frame, text="输出格式:").grid(row=2, column=0, sticky=tk.W, padx=(0, 10))
        format_frame = ttk.Frame(control_frame)
        format_frame.grid(row=2, column=1, sticky=tk.W)
        ttk.Radiobutton(format_frame, text="JSONL", variable=self.output_format, value="jsonl").pack(side=tk.LEFT)
        ttk.Radiobutton(format_frame, text="TXT", variable=self.output_format, value="txt").pack(side=tk.LEFT, padx=(20, 0))
        
        # 阈值设置
        ttk.Label(control_frame, text="阈值:").grid(row=3, column=0, sticky=tk.W, padx=(0, 10))
        threshold_frame = ttk.Frame(control_frame)
        threshold_frame.grid(row=3, column=1, sticky=tk.W)
        ttk.Scale(threshold_frame, from_=0.1, to=0.9, variable=self.threshold, 
                 orient=tk.HORIZONTAL, length=150).pack(side=tk.LEFT)
        self.threshold_label = ttk.Label(threshold_frame, text="0.5")
        self.threshold_label.pack(side=tk.LEFT, padx=(10, 0))
        
        # 处理按钮
        button_frame = ttk.Frame(control_frame)
        button_frame.grid(row=4, column=0, columnspan=3, pady=(10, 0))
        ttk.Button(button_frame, text="批量处理所有图片", command=self.process_all_images).pack(side=tk.LEFT, padx=(0, 10))
        ttk.Button(button_frame, text="处理当前图片", command=self.process_current_image).pack(side=tk.LEFT)
        
        # 图片显示区域
        image_frame = ttk.LabelFrame(main_frame, text="图片预览", padding="10")
        image_frame.grid(row=2, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), padx=(0, 10))
        image_frame.columnconfigure(0, weight=1)
        image_frame.rowconfigure(0, weight=1)
        
        # 图片显示画布
        self.canvas = tk.Canvas(image_frame, bg="white", width=400, height=400)
        self.canvas.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 图片导航
        nav_frame = ttk.Frame(image_frame)
        nav_frame.grid(row=1, column=0, pady=(10, 0))
        ttk.Button(nav_frame, text="上一张", command=self.previous_image).pack(side=tk.LEFT)
        ttk.Button(nav_frame, text="下一张", command=self.next_image).pack(side=tk.LEFT, padx=(10, 0))
        self.image_info_label = ttk.Label(nav_frame, text="0/0")
        self.image_info_label.pack(side=tk.LEFT, padx=(20, 0))
        
        # 标签显示区域
        tags_frame = ttk.LabelFrame(main_frame, text="标签结果", padding="10")
        tags_frame.grid(row=2, column=1, sticky=(tk.W, tk.E, tk.N, tk.S))
        tags_frame.columnconfigure(0, weight=1)
        tags_frame.rowconfigure(0, weight=1)
        
        # 标签文本框
        self.tags_text = tk.Text(tags_frame, wrap=tk.WORD, width=40, height=20)
        scrollbar = ttk.Scrollbar(tags_frame, orient=tk.VERTICAL, command=self.tags_text.yview)
        self.tags_text.configure(yscrollcommand=scrollbar.set)
        self.tags_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        scrollbar.grid(row=0, column=1, sticky=(tk.N, tk.S))
        
        # 状态栏
        self.status_var = tk.StringVar(value="就绪")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, relief=tk.SUNKEN)
        status_bar.grid(row=3, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(10, 0))
        
        # 绑定事件
        self.threshold.trace('w', self.update_threshold_label)
    
    def update_threshold_label(self, *args):
        """更新阈值标签显示"""
        self.threshold_label.config(text=f"{self.threshold.get():.2f}")
    
    def load_model(self):
        """加载DeepDanbooru模型"""
        self.status_var.set("正在加载模型...")
        self.root.update()
        
        try:
            self.model = DeepDanbooruModel.from_pretrained('.')
            self.model.eval()
            self.model_loaded = True
            self.status_var.set("模型加载成功！")
        except Exception as e:
            messagebox.showerror("错误", f"模型加载失败: {str(e)}")
            self.status_var.set("模型加载失败")
    
    def select_input_folder(self):
        """选择输入文件夹"""
        folder = filedialog.askdirectory(title="选择包含图片的文件夹")
        if folder:
            self.input_path_var.set(folder)
            self.load_image_files(folder)
    
    def select_output_folder(self):
        """选择输出文件夹"""
        folder = filedialog.askdirectory(title="选择输出文件夹")
        if folder:
            self.output_path_var.set(folder)
    
    def load_image_files(self, folder):
        """加载文件夹中的所有图片文件"""
        image_extensions = ['*.jpg', '*.jpeg', '*.png', '*.webp', '*.bmp']
        self.image_files = []
        
        # 使用集合来确保文件唯一性
        file_set = set()
        
        for ext in image_extensions:
            # 查找匹配的文件
            files = glob.glob(os.path.join(folder, ext))
            files.extend(glob.glob(os.path.join(folder, ext.upper())))
            
            # 添加到集合中（使用绝对路径确保唯一性）
            for file_path in files:
                abs_path = os.path.abspath(file_path)
                if abs_path not in file_set:
                    file_set.add(abs_path)
                    self.image_files.append(abs_path)
        
        # 按文件名排序
        self.image_files.sort()
        
        if self.image_files:
            self.current_index = 0
            self.display_current_image()
            self.status_var.set(f"找到 {len(self.image_files)} 张图片")
            
            # 在控制台输出文件列表，用于调试
            print(f"找到 {len(self.image_files)} 张图片:")
            for i, file_path in enumerate(self.image_files):
                print(f"  {i+1}: {os.path.basename(file_path)}")
        else:
            self.status_var.set("未找到图片文件")
    
    def display_current_image(self):
        """显示当前图片"""
        if not self.image_files or self.current_index >= len(self.image_files):
            return
        
        self.current_image_path = self.image_files[self.current_index]
        
        try:
            # 加载并调整图片大小以适应画布
            image = Image.open(self.current_image_path)
            image.thumbnail((400, 400), Image.Resampling.LANCZOS)
            
            # 转换为Tkinter可用的格式
            photo = ImageTk.PhotoImage(image)
            
            # 更新画布
            self.canvas.delete("all")
            self.canvas.create_image(200, 200, image=photo)
            self.canvas.image = photo  # 保持引用
            
            # 更新图片信息
            self.image_info_label.config(text=f"{self.current_index + 1}/{len(self.image_files)}")
            
        except Exception as e:
            messagebox.showerror("错误", f"无法加载图片: {str(e)}")
    
    def previous_image(self):
        """显示上一张图片"""
        if self.image_files and self.current_index > 0:
            self.current_index -= 1
            self.display_current_image()
    
    def next_image(self):
        """显示下一张图片"""
        if self.image_files and self.current_index < len(self.image_files) - 1:
            self.current_index += 1
            self.display_current_image()
    
    def process_current_image(self):
        """处理当前图片"""
        if not self.model_loaded:
            messagebox.showwarning("警告", "模型未加载，请稍候...")
            return
        
        if not self.current_image_path:
            messagebox.showwarning("警告", "请先选择图片")
            return
        
        try:
            # 处理图片
            image = Image.open(self.current_image_path).convert("RGB")
            tags = self.model.tag(image, threshold=self.threshold.get())
            
            # 显示标签
            self.tags_text.delete(1.0, tk.END)
            if tags and len(tags) > 0:
                tag_list = tags[0]  # 因为是单张图片，取第一个结果
                tag_text = ", ".join(tag_list)
                
                self.tags_text.insert(tk.END, f"图片: {os.path.basename(self.current_image_path)}\n")
                self.tags_text.insert(tk.END, f"标签: {tag_text}\n")
                
                self.status_var.set(f"处理完成: 找到 {len(tag_list)} 个标签")
            else:
                self.tags_text.insert(tk.END, "未找到任何标签")
                self.status_var.set("处理完成: 未找到标签")
                
        except Exception as e:
            messagebox.showerror("错误", f"处理图片时出错: {str(e)}")
            self.status_var.set("处理失败")
    
    def process_all_images(self):
        """批量处理所有图片"""
        if not self.model_loaded:
            messagebox.showwarning("警告", "模型未加载，请稍候...")
            return
        
        if not self.input_path_var.get():
            messagebox.showwarning("警告", "请先选择输入文件夹")
            return
        
        if not self.output_path_var.get():
            messagebox.showwarning("警告", "请先选择输出文件夹")
            return
        
        # 确保输出文件夹存在
        os.makedirs(self.output_path_var.get(), exist_ok=True)
        
        # 处理所有图片
        all_metadata = []
        successful = 0
        failed = 0
        
        self.status_var.set("开始批量处理...")
        self.root.update()
        
        for i, image_path in enumerate(self.image_files):
            try:
                # 更新状态
                filename = os.path.basename(image_path)
                self.status_var.set(f"处理中: {i+1}/{len(self.image_files)} - {filename}")
                self.root.update()
                
                # 处理图片
                image = Image.open(image_path).convert("RGB")
                tags = self.model.tag(image, threshold=self.threshold.get())
                
                if tags and len(tags) > 0:
                    tag_list = tags[0]  # 因为是单张图片，取第一个结果
                    tag_text = ", ".join(tag_list)
                    
                    # 创建简化的metadata条目，使用"image"而不是"file_name"
                    metadata_entry = {
                        "image": filename,
                        "text": tag_text
                    }
                    all_metadata.append(metadata_entry)
                    successful += 1
                else:
                    # 即使没有标签也创建条目
                    metadata_entry = {
                        "image": filename,
                        "text": ""
                    }
                    all_metadata.append(metadata_entry)
                    successful += 1
                    
            except Exception as e:
                print(f"处理图片 {image_path} 时出错: {e}")
                failed += 1
        
        # 保存metadata文件
        if all_metadata:
            self.save_metadata(all_metadata)
            
            # 显示结果
            self.status_var.set(f"批量处理完成: 成功 {successful}, 失败 {failed}")
            messagebox.showinfo("完成", 
                              f"批量处理完成!\n"
                              f"成功: {successful}\n"
                              f"失败: {failed}")
        else:
            self.status_var.set("没有找到可处理的图片")
            messagebox.showwarning("警告", "没有找到可处理的图片")
    
    def save_metadata(self, metadata):
        """保存metadata文件"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = self.output_path_var.get()
        
        if self.output_format.get() == "jsonl":
            # 保存为JSONL格式
            output_path = os.path.join(output_dir, f"metadata_{timestamp}.jsonl")
            with open(output_path, 'w', encoding='utf-8') as f:
                for entry in metadata:
                    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
            
            messagebox.showinfo("保存成功", f"Metadata已保存为: {output_path}")
            
            # 在控制台输出文件内容预览
            print(f"\n生成的metadata文件内容预览 (前5条):")
            for i, entry in enumerate(metadata[:5]):
                print(f"  {i+1}: {entry}")
            if len(metadata) > 5:
                print(f"  ... 还有 {len(metadata)-5} 条记录")
            
        else:  # TXT格式
            output_path = os.path.join(output_dir, f"metadata_{timestamp}.txt")
            with open(output_path, 'w', encoding='utf-8') as f:
                for entry in metadata:
                    f.write(f"image: {entry['image']}\n")
                    f.write(f"标签: {entry['text']}\n")
                    f.write("-" * 50 + "\n")
            
            messagebox.showinfo("保存成功", f"Metadata已保存为: {output_path}")

def main():
    """主函数"""
    root = tk.Tk()
    app = DeepDanbooruGUI(root)
    root.mainloop()

if __name__ == "__main__":
    main()