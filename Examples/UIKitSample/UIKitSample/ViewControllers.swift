import ShipPulseKit
import UIKit

/// First screen: a table view with two rows.
final class HomeViewController: UITableViewController {
    private let rows = ["Photo Grid", "Photo List"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ShipPulseKit Sample"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = rows[indexPath.row]
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let next: UIViewController = indexPath.row == 0 ? PhotoGridViewController() : PhotoListViewController()
        navigationController?.pushViewController(next, animated: true)
    }
}

/// Collection view of images. Scroll hitches are measured; the screen is tracked automatically.
final class PhotoGridViewController: UIViewController, UICollectionViewDataSource {
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Photo Grid"
        view.backgroundColor = .systemBackground

        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / 3), heightDimension: .fractionalWidth(1 / 3)))
        item.contentInsets = .init(top: 2, leading: 2, bottom: 2, trailing: 2)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(1 / 3)), subitems: [item])
        let layout = UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: "photo")
        collectionView.dataSource = self
        view.addSubview(collectionView)

        // MetricKit hitch time and ratio for this region while dragging or decelerating.
        collectionView.shipPulseTrackScrollHitches("PhotoGridScroll")
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Catalog.shared.photos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! PhotoCell
        cell.imageView.image = Catalog.shared.photos[indexPath.item].image(size: CGSize(width: 120, height: 120))
        return cell
    }
}

final class PhotoCell: UICollectionViewCell {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Table view of images. Scroll hitches and the row-expand animation are measured.
final class PhotoListViewController: UITableViewController {
    private var expanded: Set<Int> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Photo List"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "photo")
        tableView.shipPulseTrackScrollHitches("PhotoListScroll")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Catalog.shared.photos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let photo = Catalog.shared.photos[indexPath.row]
        let side: CGFloat = expanded.contains(photo.id) ? 120 : 56
        let cell = tableView.dequeueReusableCell(withIdentifier: "photo", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = photo.title
        content.image = photo.image(size: CGSize(width: side, height: side))
        content.imageProperties.cornerRadius = 8
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = Catalog.shared.photos[indexPath.row].id
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        // Measures hitches for this animation until it completes.
        UIView.shipPulseAnimate("ExpandRow", withDuration: 0.35) {
            tableView.reloadRows(at: [indexPath], with: .automatic)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
