import SwiftUI
import UIKit

/// 图片放缩/拖动容器：系统相册级别的看图体验。
/// 核心靠 ``ZoomableImageContainerView``（`UIScrollView` + `UIImageView`）实现，
/// 这里只是把 UIKit 拼装包成 SwiftUI 可用。
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ZoomableImageContainerView {
        let view = ZoomableImageContainerView()
        view.coordinator = context.coordinator
        view.setImage(image)
        return view
    }

    func updateUIView(_ uiView: ZoomableImageContainerView, context: Context) {
        // 只在图像实例变化时才换，避免每次 SwiftUI 重渲染都重置缩放状态。
        if uiView.currentImage !== image {
            uiView.setImage(image)
        }
    }

    final class Coordinator: NSObject {
        // 预留：以后若需要在缩放状态变化时回写 SwiftUI（例如缩放中关掉下滑 dismiss），
        // 可以在这里挂一个闭包由 container 调用。
        var onZoomStateChanged: ((Bool) -> Void)?
    }
}

/// 内部 UIKit 视图：`UIScrollView` 包 `UIImageView`，处理捏合、双击、拖拽、回弹。
final class ZoomableImageContainerView: UIView {
    private let scrollView: UIScrollView
    private let imageView: UIImageView

    fileprivate weak var coordinator: ZoomableImageView.Coordinator?

    private(set) var currentImage: UIImage?

    override init(frame: CGRect) {
        scrollView = UIScrollView()
        imageView = UIImageView()
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setup() {
        backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    func setImage(_ image: UIImage) {
        currentImage = image
        imageView.image = image
        if bounds.width > 0 && bounds.height > 0 {
            layoutContent()
        } else {
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        layoutContent()
    }

    /// 计算等比 fit 后的 imageView 尺寸，并复位缩放。
    /// 在 fit 模式下 `minimumZoomScale = 1` 正好是"撑满屏幕"，
    /// 因此 maxZoom=6 也就是相对原图最多约放大到 6 倍于适配宽度。
    private func layoutContent() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else {
            scrollView.contentSize = .zero
            return
        }
        let fit = MediaViewerLayout.fittedSize(
            imageSize: image.size,
            viewportSize: bounds.size
        )
        imageView.frame = CGRect(origin: .zero, size: fit)
        scrollView.contentSize = fit
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.setZoomScale(1, animated: false)
        centerImageViewIfNeeded()
    }

    /// 缩放回到 1 时若图片小于视图，做"等比居中"，避免图片贴在左上角。
    /// 苹果官方示例 `ScrollViewSuite` 的标准做法。
    private func centerImageViewIfNeeded() {
        let scroll = scrollView.bounds.size
        let content = scrollView.contentSize
        let horizontalInset = max(0, (scroll.width - content.width) / 2)
        let verticalInset = max(0, (scroll.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let targetScale = min(scrollView.maximumZoomScale, 2.5)
        let zoomSize = CGSize(
            width: scrollView.bounds.width / targetScale,
            height: scrollView.bounds.height / targetScale
        )
        let origin = CGPoint(
            x: max(0, point.x - zoomSize.width / 2),
            y: max(0, point.y - zoomSize.height / 2)
        )
        scrollView.zoom(
            to: CGRect(origin: origin, size: zoomSize),
            animated: true
        )
    }
}

extension ZoomableImageContainerView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageViewIfNeeded()
        coordinator?.onZoomStateChanged?(scrollView.zoomScale > scrollView.minimumZoomScale + 0.01)
    }
}
