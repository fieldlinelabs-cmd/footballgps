//
//  NativeAdCardView.swift
//  FootballGPS
//
//  Sessions一覧に挟むネイティブ広告のカード（docs/広告仕様書.md §4.1①）。
//  ネイティブ広告はUIKitのGADNativeAdViewで組み立てる決まりのため、SwiftUIからはラップして使う。
//  大きな画像・動画は出さず、アイコン・見出し・説明文・ボタンだけの小さなカードにして一覧になじませる。
//  「広告」ラベルとAdChoicesマークは必須。AdChoicesマークはadChoicesViewを指定せず、SDKが右上に自動で付ける
//  （独自のadChoicesViewはアカウントマネージャーへの申請が必要な機能のため使わない）。
//  Googleのテスト広告では表示されないため、公開後に本番の広告で表示を確認する（広告仕様書§10.1）。
//

import GoogleMobileAds
import SwiftUI
import UIKit

struct NativeAdCardView: UIViewRepresentable {
    let nativeAd: GADNativeAd

    func makeUIView(context: Context) -> GADNativeAdView {
        let adView = GADNativeAdView()

        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 8
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
        ])

        let badgeLabel = PaddedLabel()
        badgeLabel.text = "広告"
        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .systemOrange
        badgeLabel.layer.cornerRadius = 3
        badgeLabel.clipsToBounds = true
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let headlineLabel = UILabel()
        headlineLabel.font = .preferredFont(forTextStyle: .subheadline).bold()
        headlineLabel.numberOfLines = 1

        let bodyLabel = UILabel()
        bodyLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2

        var buttonConfig = UIButton.Configuration.bordered()
        buttonConfig.buttonSize = .small
        let ctaButton = UIButton(configuration: buttonConfig)
        // タップの処理はSDKが行うため、ボタン自体はタップを受け付けないようにする（AdMobの決まり）
        ctaButton.isUserInteractionEnabled = false
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        ctaButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [badgeLabel, headlineLabel])
        titleRow.spacing = 6
        titleRow.alignment = .center

        let textColumn = UIStackView(arrangedSubviews: [titleRow, bodyLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 2

        let row = UIStackView(arrangedSubviews: [iconView, textColumn, ctaButton])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            // 右上のAdChoicesマークと重ならないよう、右端に少し余白を取る
            row.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
        ])

        adView.iconView = iconView
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = ctaButton
        return adView
    }

    func updateUIView(_ adView: GADNativeAdView, context: Context) {
        guard adView.nativeAd !== nativeAd else { return }

        (adView.headlineView as? UILabel)?.text = nativeAd.headline

        (adView.bodyView as? UILabel)?.text = nativeAd.body
        adView.bodyView?.isHidden = nativeAd.body == nil

        (adView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        adView.iconView?.isHidden = nativeAd.icon == nil

        (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        adView.callToActionView?.isHidden = nativeAd.callToAction == nil

        // 各部品を設定し終えてから広告を割り当てる（表示回数・タップの計測が始まる）
        adView.nativeAd = nativeAd
    }
}

/// 「広告」ラベル用の、内側に余白を持つラベル
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
